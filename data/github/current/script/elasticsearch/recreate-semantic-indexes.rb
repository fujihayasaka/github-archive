#!/usr/bin/env ruby
# frozen_string_literal: true

# Recreate Elasticsearch indexes for Issues and Pull Requests with correct
# semantic_text mappings.
#
# Run via: bin/rails runner script/elasticsearch/recreate-semantic-indexes.rb
#
# Background:
#   The indexes are first created during codespace setup (es:reset) before the
#   inference endpoint exists, so their semantic_text field mappings are broken
#   (wrong dimensions / similarity). This script force-deletes them via the ES
#   HTTP API and recreates them through the Elastomer framework so they pick up
#   the current development configuration.
#
#   We bypass Elastomer's purge + primary_index cycle because background jobs
#   (resqued) can auto-recreate the index (via ES auto_create_index) between the
#   delete and the existence check, leaving stale mappings in place.

require "net/http"
require "json"

ES_URL = URI(ENV.fetch("ES_URL", "http://localhost:9400"))
INDEX_CLASSES = [Elastomer::Indexes::Issues, Elastomer::Indexes::PullRequests].freeze

def force_delete_index(name)
  delete_uri = URI("#{ES_URL}/#{name}")
  Net::HTTP.start(delete_uri.host, delete_uri.port) do |http|
    res = http.request(Net::HTTP::Delete.new(delete_uri))
    case res.code
    when "200"
      puts "  Deleted #{name} from Elasticsearch."
    when "404"
      puts "  #{name} did not exist in Elasticsearch; nothing to delete."
    else
      puts "  Warning: DELETE #{name} returned HTTP #{res.code}: #{res.body}"
    end
  end

  # If a background job auto-recreated the index in the meantime, delete it
  # again — the window is tiny but we guard against it.
  loop do
    check_uri = URI("#{ES_URL}/#{name}")
    break unless Net::HTTP.get_response(check_uri).code == "200"

    puts "  Index #{name} was auto-recreated; deleting again..."
    Net::HTTP.start(check_uri.host, check_uri.port) do |http|
      http.request(Net::HTTP::Delete.new(check_uri))
    end
    sleep 0.1
  end
end

app = Elastomer::App.new

INDEX_CLASSES.each do |index_class|
  name = app.send(:primary_index_name, index_class)
  puts "Recreating #{index_class.name} index (#{name})..."

  force_delete_index(name)

  index = index_class.new(name, nil)
  index.create
  app.promote_to_primary(index)
  puts "  Created #{name} with correct mappings."
  app.load_data(index)
end

puts "Done recreating indexes."
