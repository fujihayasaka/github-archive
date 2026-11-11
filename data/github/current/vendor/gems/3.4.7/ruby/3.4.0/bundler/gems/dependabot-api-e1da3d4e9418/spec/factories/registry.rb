# frozen_string_literal: true

FactoryBot.define do
  factory :registry do
    registry_type { "rubygems_server" }
    sequence(:name) { |n| "registry#{n}" }
    credentials do
      {
        url: "gem.fury.io",
        token: "${{secrets.GEMFURY}}",
      }.to_json
    end

    association :source, factory: :repo

    trait :bundler
    trait :rubygems_server

    trait :docker do
      registry_type { "docker_registry" }
      credentials do
        {
          url: "a-host.io:5000",
          username: "a",
          password: "${{secrets.DOCKER_PASSWORD}}",
        }.to_json
      end
    end

    trait :docker_compose do
      registry_type { "docker_registry" }
      credentials do
        {
          url: "a-host.io:5000",
          username: "a",
          password: "${{secrets.DOCKER_PASSWORD}}",
        }.to_json
      end
    end

    trait :git do
      registry_type { "git_source" }
      credentials do
        {
          url: "a-host.io:5000",
          username: "x-access-token",
          password: "${{secrets.GIT_PASSWORD}}",
        }.to_json
      end
    end

    trait :npm_and_yarn do
      registry_type { "npm_registry" }
      credentials do
        {
          "url" => "registry.npmjs.org",
          "token" => "${{secrets.NPM_TOKEN}}",
        }.to_json
      end
    end

    trait :bun do
      registry_type { "npm_registry" }
      credentials do
        {
          "url" => "registry.npmjs.org",
          "token" => "${{secrets.NPM_TOKEN}}",
        }.to_json
      end
    end

    trait :terraform do
      registry_type { "terraform_registry" }
      credentials do
        JSON.pretty_generate({
                               url: "https://registry.terraform.example.org",
                               token: "${{secrets.TOKEN}}",
                             })
      end
    end

    trait :goproxy_server do
      registry_type { "goproxy_server" }
      credentials do
        {
          "url" => "https://goproxy.example.com",
          "username" => "user@example.com",
          "password" => "${{secrets.GOPROXY_PASSWORD}}",
        }.to_json
      end
    end
  end
end
