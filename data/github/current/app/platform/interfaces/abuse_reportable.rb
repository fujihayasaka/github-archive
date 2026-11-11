# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AbuseReportable
      include Platform::Interfaces::Base

      description "Entities that can be reported."
      visibility :internal

      field :report_count, Integer, description: "the number of times this content has been reported", null: true, visibility: :internal
      field :top_report_reason, String, description: "the top reported reason for this content", null: true, visibility: :internal
      field :last_reported_at, Scalars::DateTime, description: "the most recent time this content was reported", null: true, visibility: :internal
      field :abuse_reports, Connections.define(Objects::AbuseReport), description: "The abuse reports received for this content.", connection: true, null: false

      def report_count
        if @context[:viewer].try(:site_admin?)
          @object.async_report_count
        else
          nil
        end
      end

      def top_report_reason
        if @context[:viewer].try(:site_admin?)
          @object.async_top_report_reason
        else
          nil
        end
      end

      def last_reported_at
        if @context[:viewer].try(:site_admin?)
          @object.async_last_reported_at
        else
          nil
        end
      end

      def abuse_reports
        return ArrayWrapper.new([]) unless @context[:viewer].try(:site_admin?)

        Platform::Loaders::RecentAbuseReportsForContent.load(@object).then do |reports|
          ArrayWrapper.new(reports)
        end
      end
    end
  end
end
