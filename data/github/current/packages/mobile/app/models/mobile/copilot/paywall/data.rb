# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      class Data
        DEFAULT_JSON_PATH = "data.json"
        PREVIEW_JSON_PATH = "preview_data.json"
        MAX_LICENSE_TYPE = "copilot_individual_max"

        class << self
          sig { returns(View) }
          def default
            @default ||= T.let(load_from_json(DEFAULT_JSON_PATH), T.nilable(View))
          end

          sig { returns(View) }
          def preview
            @preview ||= T.let(load_from_json(PREVIEW_JSON_PATH), T.nilable(View))
          end

          sig { params(view: View).returns(View) }
          def without_max(view)
            View.new(
              paywall_products: view.paywall_products.reject { |product| product.copilot_license_type == MAX_LICENSE_TYPE },
              disclaimers: view.disclaimers,
              all_features: view.all_features.map { |section| filter_section(section) }
            )
          end

          private

          sig { params(filename: String).returns(View) }
          def load_from_json(filename)
            json_path = File.join(__dir__, filename)
            data = JSON.parse(File.read(json_path), symbolize_names: true)
            View.from_hash(data)
          rescue StandardError => e
            GitHub.dogstats.increment("mobile.copilot.paywall.data_load_error", tags: ["error_class:#{e.class.name}", "file:#{filename}"])
            raise
          end

          sig { params(section: FeatureComparisonSection).returns(FeatureComparisonSection) }
          def filter_section(section)
            FeatureComparisonSection.new(
              title: section.title,
              features: section.features.map { |feature| filter_feature(feature) }
            )
          end

          sig do
            params(feature: T.any(FeatureComparisonSubsection, ChatModels))
              .returns(T.any(FeatureComparisonSubsection, ChatModels))
          end
          def filter_feature(feature)
            case feature
            when FeatureComparisonSubsection
              FeatureComparisonSubsection.new(
                title: feature.title,
                plan_rows: feature.plan_rows.reject { |plan_row| plan_row.copilot_license_type == MAX_LICENSE_TYPE }
              )
            when ChatModels
              ChatModels.new(
                title: feature.title,
                plans: feature.plans.reject { |plan| plan.copilot_license_type == MAX_LICENSE_TYPE }
              )
            else
              T.absurd(feature)
            end
          end
        end
      end
    end
  end
end
