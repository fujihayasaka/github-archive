#!/usr/bin/env ruby

# This script downloads and extracts a set of precompiled dependencies
# It should only be run from the devcontainer Dockerfile

require 'digest'
require 'shellwords'
require 'thread'

ARCH = `dpkg --print-architecture`.strip.to_sym
THREADS = []

Thread.abort_on_exception = true

def run(command)
  puts "[run] #{command}"
  system command
end

def exists(path, sha)
  File.exists?(path) && Digest::SHA256.file(path).hexdigest == sha
end

def download(checksums, name, url, extract)
  THREADS << Thread.new do
    sha = checksums.fetch(ARCH)
    path = File.join('/var/cache/downloads', name)
    if exists(path, sha)
      puts "[cached] #{path} => #{url}"
    else
      puts "[missing] #{path} => #{url}"
      for attempt in 1..10 do
        run ['curl', '--compressed', '--location', '--silent', '--fail', '--show-error', '--output', path, url].shelljoin
        break if exists(path, sha)
        sleep 2 ** attempt * 0.05
      end
    end
    raise StandardError.new("did not fetch #{url}") unless File.exists?(path)
    raise StandardError.new("checksum mismatch for #{name}: #{Digest::SHA256.file(path).hexdigest} != #{sha}") unless Digest::SHA256.file(path).hexdigest == sha
    run "#{extract} #{path.shellescape}"
  end
end

GO_VERSION, GO_SHA256_AMD64, GO_SHA256_ARM64 = File.read('.go-version').split(' ')
GO_SHA256={'amd64': GO_SHA256_AMD64, 'arm64': GO_SHA256_ARM64}

PROTOBUF_VERSION="3.11.2"
PROTOBUF_SHA256={'amd64': 'c0c666fb679a8221bed01bffeed1f80727c6c7827d0cbd8f162195efb12df9e0', 'arm64': '870cb20a5581ef60731bdc6a69f6537eb4a48d630b5904fdffcaed724c87bf3a'}
PROTOBUF_ARCH={'amd64': 'x86_64', 'arm64': 'aarch_64'}

SKEEMA_VERSION="1.11.2"
SKEEMA_SHA256={'amd64': 'fce972d2dd80d341323297d98135621b114f48988e378cbf83629a5c546e8625', 'arm64': '5cd8b5b3dd839b21fccf9833f97c205ecca97471ed5fb5c235b06154b0524cd6'}

NODE_VERSION="20.18.2"
NODE_SHA256={'amd64': 'eb5b031bdd728871c3b9a82655dbfa533bc262c0b6da1d09a86842430cef07d4', 'arm64': '319789e8a055ff80793a05e633c8c5c9226050144a09da3747225b4ec56a2a99'}
NODE_ARCH={'amd64': 'x64', 'arm64': 'arm64'}

download GO_SHA256, 'go.tar.gz', "https://go.dev/dl/go#{GO_VERSION}.linux-#{ARCH}.tar.gz", 'tar -C /usr/local/ -xf'
download PROTOBUF_SHA256, 'protoc.zip', "https://github.com/protocolbuffers/protobuf/releases/download/v#{PROTOBUF_VERSION}/protoc-#{PROTOBUF_VERSION}-linux-#{PROTOBUF_ARCH.fetch(ARCH)}.zip", 'unzip -d /usr/local/'
download SKEEMA_SHA256, 'skeema.tar.gz', "https://github.com/skeema/skeema/releases/download/v#{SKEEMA_VERSION}/skeema_#{SKEEMA_VERSION}_linux_#{ARCH}.tar.gz", 'tar -C /bin/ -xf'
download NODE_SHA256, 'node.tar.gz', "https://nodejs.org/download/release/v#{NODE_VERSION}/node-v#{NODE_VERSION}-linux-#{NODE_ARCH.fetch(ARCH)}.tar.gz", 'tar -C /usr/local/ --strip-components=1 -xf'

THREADS.map(&:join)
