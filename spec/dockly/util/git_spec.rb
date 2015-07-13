require 'spec_helper'

describe Dockly::Util::Git do
  describe '#repo' do
    it 'returns the repo for the current directory' do
      expect(subject.repo.workdir).to eq(File.expand_path('.') + '/')
    end
  end

  describe '#sha' do
    it 'returns a shortened sha for the head object' do
      expect(subject.sha).to eq(`git rev-parse --short HEAD`[0..6])
    end
  end

  describe '#ls_files' do
    it 'returns an Array of the files for the given OID' do
      expect(subject.ls_files(subject.sha).map { |hash| hash[:name] }.sort)
        .to eq(`git ls-files`.split("\n").sort)
    end
  end

  describe '#archive' do
    let(:io) { StringIO.new }
    let(:prefix) { '/gem/dockly' }
    let(:reader) { Gem::Package::TarReader.new(io.tap(&:rewind)) }

    it 'archives the current directory into the given IO' do
      subject.archive(subject.sha, prefix, io)
      reader.each do |entry|
        expect(entry.full_name).to start_with(prefix)
        orig = entry.full_name.gsub(/\A#{prefix}\//, '')
        expect(File.exist?(orig)).to be_true
        expect(entry.read).to eq(File.read(orig)) if orig.end_with?('.rb')
      end
    end
  end
end