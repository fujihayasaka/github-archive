# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class DatabaseView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stafftools::Sentry

      attr_reader :repository

      def page_title
        "#{repository.name_with_owner} - Database"
      end

      def columns
        columns = %w(id global_relay_id next_global_id created_at updated_at pushed_at public name owner_id
                      stargazer_count source_id parent_id)

        attrs  = ::Repository.attribute_names
        attrs += %w(default_branch)
        attrs -= %w(master_branch)
        attrs -= %w(disk_usage raw_data watcher_count)

        columns += attrs.sort

        columns.uniq
      end

      def association?(column)
        column[/_id/] && !column[/global_relay_id/] && !column[/next_global_id/]
      end

      def association_title(column)
        if column =~ /_by_user_id/
          column.chomp("_user_id")
        else
          column.chomp("_id")
        end
      end

      def association_value(column)
        if column == "source_id"
          repository.source_id
        elsif column == "global_relay_id"
          repository.global_relay_id
        elsif column == "next_global_id"
          repository.next_global_id
        else
          repository.send(association_title(column))
        end
      end

      def is_user?(value)
        value.is_a? ::User
      end

      def is_repo?(value)
        value.is_a? ::Repository
      end

      def human_value(column)
        value = repository.send(column)
        value.to_sentence if value.respond_to?(:to_sentence)
        value.blank? ? "N/A" : value
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        oops(column, e)
      end

      def oops(column, error)
        Failbot.report(error, "gh.repo.content.column.id": column) if Rails.env.production? || Rails.env.staging?

        sentry_link = sentry_query_link(
          [Stafftools::Sentry::DOTCOM_PROJECT_ID],
          "repo_id:#{repository.id}"
        )

        link = helpers.link_to("[#{error.class}] #{error.message}", sentry_link,
          :class       => "tooltipped tooltipped-e",
          "aria-label" => "search Sentry",
          :target      => "_blank",
          :rel         => "noopener noreferrer",
        )

        helpers.safe_join(["ERROR: ", link])
      end

    end
  end
end
