# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe Faraday::EtagCache do
  describe ".new" do
    context "without a cache" do
      it "blows up" do
        expect { described_class.new({}) }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#call" do
    subject(:request) do
      make_request(
        method: method,
        url: url,
        response: response,
        headers: headers,
      )
    end

    let(:middleware_options) { { cache: cache } }
    let(:response) { [200, { "Etag" => "x" }, "here"] }
    let(:method) { :get }
    let(:url) { "/foo" }
    let(:headers) { {} }
    let(:cache) { Rails.cache }

    before { Rails.cache.clear }

    def connection
      Faraday.new do |c|
        c.use described_class, middleware_options
        c.adapter :test do |stub|
          yield(stub) if block_given?
        end
      end
    end

    def make_request(url:, response:, method: :get, headers: {})
      connection do |stub|
        stub.send(:new_stub, method, url, headers) { response }
      end.run_request(method, url, "request data", headers)
    end

    context "for a 200 response" do
      context "to a get request" do
        let(:method) { :get }

        it "stores the response" do
          expect { request }.
            to change { cache.read("faraday_etags/http:/foo") }.
            from(nil).to(instance_of(Faraday::Env))
          expect(cache.read("faraday_etags/http:/foo")[:body]).to eq("here")
        end

        context "with an Authorization header" do
          let(:headers) { { "Authorization" => "y" } }

          before do
            allow(OpenSSL::Digest::SHA256).
              to receive(:hexdigest).with("y").and_return("a")
          end

          it "includes the hashed auth header in the cache key" do
            expect { request }.
              to change { cache.read("faraday_etags/http:/foo+a") }.
              from(nil).to(instance_of(Faraday::Env))
            expect(cache.read("faraday_etags/http:/foo+a")[:body]).to eq("here")
          end
        end

        context "when there's already a stored response" do
          before do
            old_response = [200, { "Etag" => "x" }, "old"]
            make_request(method: method, url: url, response: old_response)
          end

          it "returns the new response" do
            expect(request.env[:body]).to eq("here")
          end

          it "includes details of the etag on the request headers" do
            expect(request.env[:request_headers]["If-None-Match"]).to eq("x")
          end

          it "updates the cache" do
            expect { request }.
              to change { cache.read("faraday_etags/http:/foo")[:body] }.
              from("old").to("here")
          end
        end

        context "without an Etag" do
          let(:response) { [200, {}, "here"] }

          it "does not store the response" do
            expect { request }.
              not_to change { cache.read("faraday_etags/http:/foo") }
          end
        end
      end

      context "to a head request" do
        let(:method) { :head }

        it "stores the response" do
          expect { request }.
            to change { cache.read("faraday_etags/http:/foo") }.
            from(nil).to(instance_of(Faraday::Env))
          expect(cache.read("faraday_etags/http:/foo")[:body]).to eq("here")
        end
      end

      context "to a post request" do
        let(:method) { :post }

        it "does not store the response" do
          expect { request }.
            not_to change { cache.read("faraday_etags/http:/foo") }
        end
      end
    end

    context "for a non-200 response" do
      let(:response) { [202, { "Etag" => "x" }, "here"] }

      it "does not store the response" do
        expect { request }.
          not_to change { cache.read("faraday_etags/http:/foo") }
      end
    end

    context "for a 304 response" do
      before do
        make_request(
          method: method,
          url: url,
          response: [200, { "Etag" => "x" }, "here"],
        )
      end

      let(:response) { [304, { "Etag" => "x" }, "Blob"] }

      it "does not update the cached response" do
        expect { request }.
          not_to change { cache.read("faraday_etags/http:/foo")[:body] }
      end

      it "returns the cached response" do
        expect(request.env[:body]).to eq("here")
      end
    end
  end
end
