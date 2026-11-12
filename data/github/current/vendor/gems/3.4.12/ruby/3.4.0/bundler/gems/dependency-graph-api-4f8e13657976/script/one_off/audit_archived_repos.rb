#!/usr/bin/env ruby
# Audit repos and delete the ones that have been archived!
# Usage: script/one_off/audit_archived_repos [-w] [--start=INDEX]

require "optparse"
require_relative "../../config/environment"

checkpoint = Checkpoint.find_or_create_by(name: "audit_archived_repos")
last_processed_id = checkpoint.last_checkpointed_id || 0

options = { delete: false, index: last_processed_id }
OptionParser.new do |opts|
  opts.on("-w", "--write", "Delete archived repos from database") do
    options[:delete] = true
  end

  opts.on("--start=INDEX", "Start at a particular repo index") do |index|
    options[:index] = index.to_i
  end
end.parse!

def audit_repos_in_batches(options, checkpoint)
  throttler = Freno::Throttler.new(client: Freno.client, app: :dependency_graph)
  puts "starting repos audit in #{options[:delete] ? 'deletion' : 'safe'} mode!"
  puts "starting with index #{options[:index]}"
  begin
    deleted_count = 0
    Repository.select(:id, :github_repository_id).in_batches(start: options[:index]).each_with_index do |batch, number|
      puts "looking through batch #{number + 1}"
      Checkpoint.where(name: checkpoint.name).update(last_checkpointed_id: batch.first.id) if options[:delete]
      github_ids = batch.collect(&:github_repository_id)
      archived_ids = GitHub::Repository.where({ id: github_ids, maintained: false }).pluck(:id)
      unless archived_ids.empty?
        if options[:delete]
          throttler.throttle(:"dependency-graph") do
            puts "found archived repositories to delete in this batch!"
            Repository.where(github_repository_id: archived_ids).in_batches(of: 50).each_with_index do |delete_batch, delete_number|
              puts "deleting sub-batch #{delete_number + 1} of batch #{number + 1}"
              delete_batch.destroy_all
            end
          end
        end
        puts "#{options[:delete] ? 'deleted' : 'would delete'} repos with github_repository_ids #{archived_ids.join(', ')}"
        deleted_count += archived_ids.count
      end
    end
    puts "done auditing repos! #{deleted_count} archived repositories #{options[:delete] ? 'deleted' : 'would be deleted'}."
  rescue => e
    puts "Exception!"
    Failbot.report(e)
    raise e
  end
end

Instrument.time("dg.audit_archived_repos") do
  audit_repos_in_batches(options, checkpoint)
end
