# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class SyncIssueEventDetailsWithRawData < Base
      include GitHub::UTF8

      class IssueEventCoder < Coders::Base
        data_accessors \
          :after_commit_oid,
            :before_commit_oid,
            :card_id,
            :column_name,
            :deployment_id,
            :deployment_status_id,
            :label_id,
            :label_name,
            :label_color,
            :label_text_color,
            :lock_reason,
            :message,
            :milestone_id,
            :milestone_title,
            :performed_by_project_workflow_action_id,
            :previous_column_name,
            :pull_request_review_id,
            :pull_request_review_state_was,
            :ref,
            :review_request_id,
            :state_reason,
            :subject_id,
            :subject_type,
            :title_is,
            :title_was
      end

      class IssueEvent < ApplicationRecord::Domain::IssuesPullRequests
        self.table_name = :issue_events

        serialize :raw_data, coder: Coders::Handler.new(Coders::IssueEventCoder, compressor: GitHub::ZPack)
      end

      class IssueEventDetail < ApplicationRecord::Domain::IssuesPullRequests
        self.table_name = :issue_event_details

        include GitHub::Validations

        attribute :milestone_title, StringFromBinary.new
        attribute :title_is, StringFromBinary.new
        attribute :title_was, StringFromBinary.new
        attribute :message, StringFromBinary.new
        attribute :column_name, StringFromBinary.new
        attribute :previous_column_name, StringFromBinary.new
        attribute :label_name, StringFromBinary.new

        # VARBINARY limit from the database
        UTF8_BYTESIZE_LIMIT = 1024

        validates :milestone_title, unicode: true, bytesize: { maximum: UTF8_BYTESIZE_LIMIT }
        validates :title_is, unicode: true, bytesize: { maximum: UTF8_BYTESIZE_LIMIT }
        validates :title_was, unicode: true, bytesize: { maximum: UTF8_BYTESIZE_LIMIT }
        validates :message, unicode: true, length: { maximum: 1000 }
        validates :repository_id, presence: true, on: :create
      end

      iterate_over :database_table, params: {
        model_class: IssueEvent,
        columns: %i[raw_data],
        conditions: "raw_data IS NOT NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        details = IssueEventDetail.where(issue_event_id: items.keys).index_by(&:issue_event_id)

        IssueEvent.where(id: items.keys).find_each do |issue_event|
          next unless issue_event.has_attribute?(:raw_data)

          detail = details.fetch(issue_event.id) do
            IssueEventDetail.new(issue_event_id: issue_event.id, repository_id: issue_event.repository_id)
          end

          detail.assign_attributes(normalise_attributes(issue_event.raw_data.to_h))

          if detail.changed?
            dry_run_log = dry_run? ? " (dry run)" : ""
            log("Updating IssueEventDetail #{detail.id} / IssueEvent #{issue_event.id} with #{detail.changes_to_save}#{dry_run_log}")
          end

          unless detail.valid?
            log("Invalid IssueEventDetail #{detail.id} / IssueEvent #{issue_event.id}: #{detail.errors.full_messages.join(" - ")}")
            next
          end

          next if dry_run?

          write_to(model_class: IssueEventDetail) do
            try_times(5) { detail.save! }
          end
        end
      end

      sig { params(attrs: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def normalise_attributes(attrs)
        attrs.symbolize_keys.map do |key, value|
          value = utf8(value) if value&.is_a? String
          value = case key
          when :milestone_title, :title_is, :title_was, :label_name, :column_name, :previous_column_name
            value.truncate_bytes(IssueEventDetail::UTF8_BYTESIZE_LIMIT, omission: nil)
          when :message
            value.first(1000)
          else
            value
          end

          [key, value]
        end.to_h
      end

      sig { params(times: Integer, blk: T.proc.void).void }
      def try_times(times = 5, &blk)
        count = 1
        begin
          yield
        rescue => e
          if count >= times
            raise e
          else
            count += 1
            GitHub::Throttler.wait(count)
            retry
          end
        end
      end
    end
  end
end

if $0 == __FILE__
  args = GitHub::Transitions::Arguments.parse(ARGV)
  GitHub::Transitions::SyncIssueEventDetailsWithRawData.new(args).run
end
