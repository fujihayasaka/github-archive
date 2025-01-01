# typed: true
# frozen_string_literal: true
module GitHub
  module Config
    module ActionsScaleUnitDomains
      ACTIONS_SCALE_UNIT_DOMAINS = []
      File.foreach(File.expand_path("actions_scale_unit_domains.txt", __dir__)) do |line|
        ACTIONS_SCALE_UNIT_DOMAINS << line.chomp unless line.start_with?("#")
      end

      # GitHub Actions scale unit domains
      #
      # Returns an array of domains that are assigned to GitHub Actions scale units.
      def actions_scale_unit_domains
        return @actions_scale_unit_domains if defined?(@actions_scale_unit_domains)
        if GitHub.enterprise?   # GHES
          @actions_scale_unit_domains ||= []
        else                    # non-GHES (dotcom and Proxima)
          @actions_scale_unit_domains ||= ACTIONS_SCALE_UNIT_DOMAINS
        end
      end
    end
  end
  extend Config::ActionsScaleUnitDomains
end
