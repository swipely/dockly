class Dockly::BuildCache::Docker < Dockly::BuildCache::Base
  attr_accessor :image

  def execute!
    ensure_present! :image
    super
    image
  end

  def run_build
    container = image.run(['/bin/bash', '-lc', "cd #{command_directory} && #{build_command}"])
    status = container.wait(3600)['StatusCode'] # 1 hour max timeout
    raise "Build Cache `#{build_command}` failed to run." unless status.zero?
    cache = copy_output_dir(container)
    debug "pushing #{output_directory} to s3"
    push_to_s3(cache)
    cache.close
    self.image = container.commit
  end

  def push_cache(version)
    ensure_present! :output_dir
    if cache = pull_from_s3(version)
      debug "inserting to #{output_directory}"
      container = image.run("mkdir -p #{File.dirname(output_directory)}")
      image_with_dir = container.tap { |c| c.wait }.commit
      self.image = image_with_dir.insert_local(
        'localPath' => cache.path,
        'outputPath' => File.dirname(output_directory)
      )
      cache.close
    else
      info "could not find #{s3_object(version)}"
    end
  end

  def copy_output_dir(container)
    ensure_present! :output_dir
    file_path = File.join(tmp_dir,s3_object(hash_output))
    FileUtils.mkdir_p(File.dirname(file_path))
    file = File.open(file_path, 'w+b')
    container.wait(3600) # 1 hour max timeout
    container.copy(output_directory) { |chunk| file.write(chunk) }
    file.tap(&:rewind)
  end

  def hash_output
    ensure_present! :image, :hash_command
    @hash_output ||= begin
      resp = ""
      container = image.run(["/bin/bash", "-lc", "cd #{command_directory} && #{hash_command}"])
      container.attach { |source,chunk| resp += chunk }
      status = container.wait['StatusCode']
      raise "Hash Command `#{hash_command}` failed to run" unless status.zero?
      resp.strip
    end
  end
end