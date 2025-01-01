# typed: strict
# frozen_string_literal: true

module Copilot
  class UsageMetric < ApplicationRecord::Copilot
    extend T::Sig
    include GitHub::Memoizer
    include ::Instrumentation::Model
    self.table_name = "copilot_usage_metrics"
    self.strict_loading_by_default = true

    belongs_to :organization, class_name: "::Organization", strict_loading: false
    belongs_to :business, class_name: "::Business", strict_loading: false
    belongs_to :team, class_name: "::Team", strict_loading: false
    belongs_to :enterprise_team, class_name: "::EnterpriseTeam", strict_loading: false

    scope :last_28_days, -> { where("date >= ?", 28.days.ago) }
    scope :between_dates, ->(start_date, end_date) do
      if start_date && end_date
        where(date: start_date..end_date)
      elsif start_date
        where("date >= ?", start_date)
      elsif end_date
        where("date <= ?", end_date)
      else
        where("date >= ?", 28.days.ago)
      end
    end

    scope :for_organization, ->(organization) { where(organization: organization) }

    scope :for_business, ->(business) { where(business: business) }

    scope :for_team, ->(team) { where(team: team) }

    scope :for_enterprise_team, ->(enterprise_team) { where(enterprise_team: enterprise_team) }

    enum :editor, {
      unknown: 0,
      vscode: 1,
      visual_studio: 2,
      jetbrains: 3,
      vim: 4,
      neovim: 5,
      emacs: 6,
      xcode: 7,
      sublime_text: 8,
      eclipse: 9,
    }, prefix: false

    sig { returns(String) }
    memoize def actual_language_name
      if language_name_id == 0 || language_name_id.nil?
        return language || "unknown"
      end

      language_name = LanguageName.find_by(id: language_name_id)
      return T.must(language_name.to_s) if language_name.present?

      # if we don't have a language by now, we screwed up and hopefully threw an error somewhere already
      # by somewhere, I mean in the copilot-usage-service
      "unknown"
    end

    sig { returns(T::Boolean) }
    def is_totals_row?
      language == "all" && editor == "unknown"
    end
  end
end
