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

GOLANGCI_LINT_VERSION="1.61.0"
GOLANGCI_LINT_SHA256={'amd64': '77cb0af99379d9a21d5dc8c38364d060e864a01bd2f3e30b5e8cc550c3a54111', 'arm64': 'af60ac05566d9351615cb31b4cc070185c25bf8cbd9b09c1873aa5ec6f3cc17e'}

NODE_VERSION="20.12.2"
NODE_SHA256={'amd64': 'f8f9b6877778ed2d5f920a5bd853f0f8a8be1c42f6d448c763a95625cbbb4b0d', 'arm64': '2dc8ffa0da135bf493f881d2d38aac610772c801bb7b6208fcc5de9350f119f7'}
NODE_ARCH={'amd64': 'x64', 'arm64': 'arm64'}

download GO_SHA256, 'go.tar.gz', "https://go.dev/dl/go#{GO_VERSION}.linux-#{ARCH}.tar.gz", 'tar -C /usr/local/ -xf'
download PROTOBUF_SHA256, 'protoc.zip', "https://github.com/protocolbuffers/protobuf/releases/download/v#{PROTOBUF_VERSION}/protoc-#{PROTOBUF_VERSION}-linux-#{PROTOBUF_ARCH.fetch(ARCH)}.zip", 'unzip -d /usr/local/'
download SKEEMA_SHA256, 'skeema.tar.gz', "https://github.com/skeema/skeema/releases/download/v#{SKEEMA_VERSION}/skeema_#{SKEEMA_VERSION}_linux_#{ARCH}.tar.gz", 'tar -C /bin/ -xf'
download GOLANGCI_LINT_SHA256, 'golangci-lint.tar.gz', "https://github.com/golangci/golangci-lint/releases/download/v#{GOLANGCI_LINT_VERSION}/golangci-lint-#{GOLANGCI_LINT_VERSION}-linux-#{ARCH}.tar.gz", 'tar -C /bin/ --strip-components=1 -xf'
download NODE_SHA256, 'node.tar.gz', "https://mirrors.dotsrc.org/nodejs/release/v#{NODE_VERSION}/node-v#{NODE_VERSION}-linux-#{NODE_ARCH.fetch(ARCH)}.tar.gz", 'tar -C /usr/local/ --strip-components=1 -xf'

THREADS.map(&:join)
