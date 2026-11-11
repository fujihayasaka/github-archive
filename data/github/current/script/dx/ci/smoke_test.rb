#!/usr/bin/env safe-ruby
# frozen_string_literal: true

require "json"
require "tempfile"
require "tmpdir"
require "net/http"
require "uri"

class SmokeTest

  def initialize
    @script_path = File.dirname(__FILE__)
    @id = Time.now.to_i
    @pat = "ghp_MonalisaTheOctoPatMonalisaTheOctoPat"
    @max_attempts = 50
    @retry_sleep_time = 10
  end

  def http_get(url, headers = {})
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri)
    headers.each { |key, value| request[key] = value }
    http.request(request)
  end

  def print_response_body(response)
    if response.nil? || response.body.nil?
      puts "Response body: (no response body)"
      return
    end

    if response.body.length > 200
      puts "Response body:\n#{response.body[0..200]}..."
    else
      puts "Response body:\n#{response.body}"
    end
  end

  def test_server_status
    url = "http://127.0.0.1:3000/status"
    puts "Checking for 200 response from #{url}"

    (1..@max_attempts).each do |i|
      begin
        response = http_get(url)

        if response.code == "200" && response.body.include?("GitHub lives!")
          puts "Server un-authenticated validation passed."
          return
        else
          puts "Server un-authenticated validation failed (attempt #{i}/#{@max_attempts}). Response code: #{response.code}"
          print_response_body(response)
        end
      rescue => e
        puts "Server un-authenticated validation failed (attempt #{i}/#{@max_attempts}). Error: #{e.message}"
      end

      if i != @max_attempts
        puts "Retrying in #{@retry_sleep_time} seconds..."
        sleep @retry_sleep_time
      end
    end

    puts "Server validation failed despite #{@max_attempts} attempts."
    abort "Server validation failed"
  end

  def test_server_authenticated
    url = "http://localhost:3000/api/v3/user"
    puts "Testing authenticated endpoint: #{url}"

    (1..@max_attempts).each do |i|
      begin
        response = http_get(url, { "Authorization" => "token #{@pat}" })

        if response.code == "200"
          user_data = JSON.parse(response.body)
          if user_data.is_a?(Hash) && user_data["login"] == "monalisa"
            puts "Server authenticated validation passed. Logged in as: monalisa"
            return
          else
            puts "Server authenticated validation failed (attempt #{i}/#{@max_attempts}). Wrong user or invalid response."
            print_response_body(response)
          end
        else
          puts "Server authenticated validation failed (attempt #{i}/#{@max_attempts}). Response code: #{response.code}"
          print_response_body(response)
        end
      rescue => e
        puts "Server authenticated validation failed (attempt #{i}/#{@max_attempts}). Error: #{e.message}"
      end

      if i != @max_attempts
        puts "Retrying in #{@retry_sleep_time} seconds..."
        sleep @retry_sleep_time
      end
    end

    puts "Server authenticated validation failed despite #{@max_attempts} attempts."
    abort "Server authenticated validation failed"
  end
end

test = SmokeTest.new

test.test_server_status
test.test_server_authenticated
