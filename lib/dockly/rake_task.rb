require 'rake'
require 'dockly'

class Rake::DebTask < Rake::Task
  def needed?
    raise "Package does not exist" if package.nil?
    !!ENV['FORCE'] || !package.exists?
  end

  def package
    Dockly::Deb[name.split(':').last.to_sym]
  end
end

class Rake::RpmTask < Rake::Task
  def needed?
    raise "Package does not exist" if package.nil?
    !!ENV['FORCE'] || !package.exists?
  end

  def package
    Dockly::Rpm[name.split(':').last.to_sym]
  end
end

class Rake::DockerTask < Rake::Task
  def needed?
    raise "Docker does not exist" if docker.nil?
    !docker.exists?
  end

  def docker
    Dockly::Docker[name.split(':').last.to_sym]
  end
end

module Rake::DSL
  def deb(*args, &block)
    Rake::DebTask.define_task(*args, &block)
  end

  def rpm(*args, &block)
    Rake::RpmTask.define_task(*args, &block)
  end

  def docker(*args, &block)
    Rake::DockerTask.define_task(*args, &block)
  end
end

namespace :dockly do
  task :load do
    raise "No dockly.rb found!" unless File.exist?('dockly.rb')
  end

  prepare_targets = []
  upload_targets = []
  build_targets = []
  copy_targets = []

  namespace :deb do
    Dockly.debs.values.each do |inst|
      namespace :prepare do
        task inst.name => 'dockly:load' do |name|
          inst.create_package!
        end
      end

      namespace :upload do
        deb inst.name => 'dockly:load' do |name|
          inst.upload_to_s3
        end
      end

      namespace :copy do
        task inst.name => 'dockly:load' do |name|
          inst.copy_from_s3(Dockly::History.duplicate_build_sha[0..6])
        end
      end

      deb inst.name => [
        'dockly:load',
        "dockly:deb:prepare:#{inst.name}",
        "dockly:deb:upload:#{inst.name}"
      ]
      prepare_targets << "dockly:deb:prepare:#{inst.name}"
      upload_targets << "dockly:deb:upload:#{inst.name}"
      copy_targets << "dockly:deb:copy:#{inst.name}"
      build_targets << "dockly:deb:#{inst.name}"
    end
  end

  namespace :rpm do
    Dockly.rpms.values.each do |inst|
      namespace :prepare do
        task inst.name => 'dockly:load' do |name|
          inst.create_package!
        end
      end

      namespace :upload do
        rpm inst.name => 'dockly:load' do |name|
          inst.upload_to_s3
        end
      end

      namespace :copy do
        task inst.name => 'dockly:load' do |name|
          inst.copy_from_s3(Dockly::History.duplicate_build_sha[0..6])
        end
      end

      rpm inst.name => [
        'dockly:load',
        "dockly:rpm:prepare:#{inst.name}",
        "dockly:rpm:upload:#{inst.name}"
      ]
      prepare_targets << "dockly:rpm:prepare:#{inst.name}"
      upload_targets << "dockly:rpm:upload:#{inst.name}"
      copy_targets << "dockly:rpm:copy:#{inst.name}"
      build_targets << "dockly:rpm:#{inst.name}"
    end
  end

  namespace :docker do
    Dockly.dockers.values.each do |inst|
      # For backwards compatibility
      namespace :noexport do
        task inst.name => "dockly:docker:prepare:#{inst.name}"
      end

      namespace :prepare do
        task inst.name => 'dockly:load' do
          Thread.current[:rake_task] = inst.name
          inst.generate_build
        end
      end

      namespace :upload do
        task inst.name => 'dockly:load' do
          Thread.current[:rake_task] = inst.name
          inst.export_only
        end
      end

      namespace :copy do
        task inst.name => 'dockly:load' do
          Thread.current[:rake_task] = inst.name
          inst.copy_from_s3(Dockly::History.duplicate_build_sha[0..6])
        end
      end

      docker inst.name => [
        'dockly:load',
        "dockly:docker:prepare:#{inst.name}",
        "dockly:docker:upload:#{inst.name}"
      ]

      # Docker image will be generated by 'dockly:deb:package'
      unless inst.s3_bucket.nil?
        prepare_targets << "dockly:docker:prepare:#{inst.name}"
        upload_targets << "dockly:docker:upload:#{inst.name}"
        copy_targets << "dockly:docker:copy:#{inst.name}"
        build_targets << "dockly:docker:#{inst.name}"
      end
    end
  end

  multitask :prepare_all => prepare_targets
  multitask :upload_all => upload_targets
  multitask :build_all => build_targets
  multitask :copy_all => copy_targets

  task :build_or_copy_all do
    if Dockly::History.duplicate_build?
      Rake::Task['dockly:copy_all'].invoke
    else
      Rake::Task['dockly:build_all'].invoke
      Dockly::History.write_content_tag!
      Dockly::History.push_content_tag!
    end
  end
end
