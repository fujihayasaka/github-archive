# frozen_string_literal: true

require "test_helper"
require "rake"

class ImportRakeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    AdvisoryDB::Application.load_tasks if Rake::Task.tasks.empty?
  end

  # currently there is 2 importers which should be run on automated basis
  # this test set checks:
  # - only the expected count of import jobs is enqueued
  # - each of the expected import jobs is enqueued
  # - No exceptions happen in rake task

  test "rake advisory_db:import:all runs without error" do
    assert_nothing_raised do
      # check for the jobs for the importers that do not have `disable_auto_import`
      assert_enqueued_jobs(6) do
        assert_enqueued_with(job: ImportJob, args: ["nvd"]) do
          assert_enqueued_with(job: ImportJob, args: ["pypa_advisory"]) do
            assert_enqueued_with(job: ImportJob, args: ["rustsec"]) do
              assert_enqueued_with(job: ImportJob, args: ["friends_of_php"]) do
                assert_enqueued_with(job: ImportJob, args: ["rubysec"]) do
                  assert_enqueued_with(job: ImportJob, args: ["go"]) do
                    Rake::Task["advisory_db:import:all"].invoke
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  test "rake advisory_db:import:backfill runs the BackfillImporter with default options" do
    assert_enqueued_with(job: ImportJob, args: ["backfill"]) do
      Rake::Task["advisory_db:import:backfill"].invoke
    end
  end
end
