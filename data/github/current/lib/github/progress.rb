# typed: true
# frozen_string_literal: true

# GitHub::Progress is a shared library for tracking the progress of a set of
# distributed tasks.
#
# For example, you may have a job responsible for identifying work to be done
# and enqueueing other jobs to actually do the work. Because identification and
# performance of the work may happen concurrently, it can be difficult to
# detect the moment at which all assigned tasks are complete.
#
# GitHub::Progress uses tracks two counters: a numerator and a denominator. The
# denominator represents the number of tasks expected to be done. The numerator
# represents the number of tasks actually done. A third data point is important
# in preventing false positive completion. GitHub::Progress is also aware of
# whether the denominator is "locked" meaning that no more tasks to do will be
# discovered.
#
# If at any point, the denominator is locked and the numerator is equal to
# (or greater than) the denominator, progress is considered complete.
#
# The GitHub::Progress library has two outputs: Active Support instrumentation
# and Hydro messages. Instrumentation events can be subscribed to by the
# following names: "start.progress", "update.progress", and "stop.progress".
# Each event brings with it a payload containing all known data for the
# tracked progress.
#
#     GitHub.subscribe("update.progress") do |event|
#       update_slack_progress_bar(event)
#     end
#
# All of the events emitted by Active Support instrumentation are also
# published to Hydro via "github.progress.v0.ProgressUpdate" messages. The
# payload is nearly identical to the instrumented events.
#
# To use GitHub::Progress, build a GitHub::Progress::Client and use its
# public API. The client is fully asynchronous, publishing to Hydro via
# "github.progress.v0.ProgressEvent" messages. The Hydro ProgressProcessor
# leverages a GitHub::Progress::Server to process the messages in Redis.
#
# Any stalled/abandoned progress is automatically cleaned up by the
# StopAllStalledProgressJob according to your progress's configured stall
# duration.
#
#     class FindWorkToDoJob < ApplicationJob
#       def perform(last_task_id = nil)
#         new_tasks = fetch_new_tasks(last_task_id)
#         progress = GitHub::Progress::Client.new("some_unique_key_123")
#
#         if new_tasks.none?
#           progress.lock_denominator
#         else
#           new_tasks.each do |task|
#             ActuallyDoWorkJob.perform_later(task.id)
#             progress.increment_denominator
#           end
#
#           self.class.perform_later(new_tasks.last.id)
#         end
#       end
#     end
#
#     class ActuallyDoWorkJob < ApplicationJob
#       def perform(task_id)
#         task = Task.find(task_id)
#         progress = GitHub::Progress::Client.new("some_unique_key_123")
#
#         task.do_work!
#       ensure
#         progress.increment_numerator
#       end
#     end
#
# The example above will emit "complete" instrumentation as soon as all the
# work to do is found _and_ done. Note that we increment the numerator
# regardless of whether the work performed was successful, since we are not
# retrying. If you retry your tasks, be sure to only increment the numerator
# once (at most) per task.
module GitHub
  module Progress
    autoload :Client, "github/progress/client"
    autoload :Server, "github/progress/server"
  end
end
