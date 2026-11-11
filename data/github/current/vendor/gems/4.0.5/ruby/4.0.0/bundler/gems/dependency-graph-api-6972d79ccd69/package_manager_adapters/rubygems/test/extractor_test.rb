require "test_helper"
require "extractor"

describe Extractor do
  before do
    FakeSink.reset
    reset_database

    @sink = Thread.new { FakeSink.run! }
    @sink.abort_on_exception
    sleep 0.5

    @rake = Models::Rubygem.create!(name: "rake")
    @rails = Models::Rubygem.create!(name: "rails")
    @rails.create_linkset!(code: "https://github.com/rails/rails")

    v1 = @rails.versions.create!({
      number:      "5.0.0.beta",
      description: "Beta MVC",
      authors:     "DHH",
      built_at:    Time.new(2016, 10, 10),
    })
    v1.dependencies.create!({
      rubygem:      @rake,
      requirements: ">= 11.1"
    })
    v1.gem_downloads.create!(count: 5)
    v1.gem_downloads.create!(count: 5)

    v2 = @rails.versions.create!({
      number:      "5.0.0",
      description: "MVC",
      built_at:    Time.new(2016, 10, 11),
    })
    v2.dependencies.create!({
      rubygem:      @rake,
      scope:        "development",
      requirements: ">= 11.2"
    })

    Extractor.run(sink_proxy_url: "http://localhost:7788")
  end

  after do
    @sink.kill
  end

  it "extracts those gems" do
    assert_equal 2, FakeSink.package_releases.count

    assert_includes FakeSink.package_releases, {
      package_manager: "rubygems",
      package_name: "rails",
      version: "5.0.0.beta",
      description: "Beta MVC",
      authors: "DHH",
      download_count: 10,
      external_id: "1",
      source_url: "https://github.com/rails/rails",
      home_url: nil,
      docs_url: nil,
      published_at: Time.new(2016, 10, 10).to_i,
      unpublished_at: nil,
      dependencies: [
        {
          package_name: "rake",
          requirements: ">= 11.1",
          scope: "runtime",
        }.stringify_keys
      ]
    }.stringify_keys

    assert_includes FakeSink.package_releases.drop(1), {
      package_manager: "rubygems",
      package_name: "rails",
      version: "5.0.0",
      description: "MVC",
      authors: nil,
      download_count: 0,
      external_id: "2",
      source_url: "https://github.com/rails/rails",
      home_url: nil,
      docs_url: nil,
      published_at: Time.new(2016, 10, 11).to_i,
      unpublished_at: nil,
      dependencies: [
        {
          package_name: "rake",
          requirements: ">= 11.2",
          scope: "development",
        }.stringify_keys
      ]
    }.stringify_keys
  end

  it "only imports new releases" do
    v3 = @rails.versions.create!({
      number:      "5.1.0",
      description: "NEXT LEVEL MVC"
    })
    v3.dependencies.create!({
      rubygem:      @rake,
      requirements: ">= 11.3"
    })

    Extractor.run(sink_proxy_url: "http://localhost:7788")

    assert_equal 3, FakeSink.package_releases.count
  end
end
