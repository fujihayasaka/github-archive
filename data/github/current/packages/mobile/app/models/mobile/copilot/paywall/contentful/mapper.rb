# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      module Contentful
        class Mapper

          # Plan IDs for individual/mobile paywall (Free, Pro, Pro+)
          PLAN_IDS = T.let(%w[free pro pro_plus].freeze, T::Array[String])

          # Maps status values from Contentful to icon names
          # These must match valid values in Platform::Enums::MobileCopilotPaywallIcon
          STATUS_TO_ICON = T.let({
            "Check" => "check",
            "Dash" => "none",
            "Refresh" => "reload",
            "X" => "none",
            "Unlimited" => "unlimited",
            "Enabled" => "check",
            "Disabled" => "none"
          }.freeze, T::Hash[String, String])

          # Mobile-specific disclaimers (not available in Contentful marketing content)
          MOBILE_DISCLAIMERS = T.let([
            "Option to purchase additional premium requests not available to users that subscribe or have subscribed to Pro or Pro+ through GitHub Mobile (a platform)."
          ].freeze, T::Array[String])

          # Titles that indicate a chat models section
          CHAT_MODELS_TITLES = T.let([
            "models in copilot chat",
            "available models in chat",
            "available models"
          ].freeze, T::Array[String])

          sig { params(contentful_data: T::Hash[String, T.untyped]).returns(View) } # rubocop:todo Sorbet/ForbidTUntyped
          def self.map(contentful_data)
            template = contentful_data["template"]
            content = template&.dig("content") || []

            # Find hero section (contains pricing) and comparison section
            hero_section = content.find { |c| c["title"]&.include?("Hero") }
            comparison_section = content.find { |c| c["title"]&.include?("Comparison") }

            View.new(
              paywall_products: extract_products(hero_section),
              disclaimers: MOBILE_DISCLAIMERS,
              all_features: extract_feature_sections(comparison_section)
            )
          end

          # Extract products from the hero section's pricing options
          sig { params(hero_section: T.nilable(T::Hash[String, T.untyped])).returns(T::Array[Product]) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.extract_products(hero_section)
            return [] if hero_section.nil?

            hero_content = hero_section["content"] || []
            pricing_options = hero_content.find { |c| c["title"]&.include?("PricingOptions") }
            return [] if pricing_options.nil?

            pricing_groups = pricing_options["content"] || []

            pricing_groups.each_with_object([]) do |group, products|
              items = group["items"] || []
              items.each do |item|
                product = map_pricing_item_to_product(item)
                # Only include individual plans (Free, Pro, Pro+) for mobile paywall
                if %w[copilot_free copilot_individual copilot_individual_pro_plus].include?(product.copilot_license_type)
                  products << product
                end
              end
            end
          end

          sig { params(item: T::Hash[String, T.untyped]).returns(Product) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.map_pricing_item_to_product(item)
            title = extract_rich_text(item["heading"])
            description = extract_rich_text(item["description"])
            feature_list = item["feature_list"] || []

            # Find features header and features
            features_header = ""
            features = []

            feature_list.each do |f|
              if f["variant"].nil?
                # This is a header item
                features_header = extract_rich_text(f["heading"])
              else
                # This is a feature item
                features << ProductFeature.new(
                  title: extract_rich_text(f["description"])
                )
              end
            end

            Product.new(
              title: title,
              subtitle: description.presence,
              features_header: features_header,
              copilot_license_type: title_to_license_type(title),
              features: features
            )
          end

          # Extract feature comparison sections from the comparison section
          sig { params(comparison_section: T.nilable(T::Hash[String, T.untyped])).returns(T::Array[FeatureComparisonSection]) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.extract_feature_sections(comparison_section)
            return [] if comparison_section.nil?

            comparison_content = comparison_section["content"] || []
            groups_container = comparison_content.find { |c| c["title"]&.include?("Comparison groups") }
            return [] if groups_container.nil?

            feature_groups = groups_container["content"] || []
            feature_groups.map { |group| map_feature_group(group) }
          end

          sig { params(group: T::Hash[String, T.untyped]).returns(FeatureComparisonSection) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.map_feature_group(group)
            title = group["heading"] || ""
            features = group["content"] || []

            mapped_features = features.map { |feature| map_comparison_feature_or_models(feature) }

            FeatureComparisonSection.new(
              title: title,
              features: mapped_features
            )
          end

          # Maps a feature to either a comparison subsection or chat models based on content
          # rubocop:todo Sorbet/ForbidTUntyped
          sig do
            params(feature: T::Hash[String, T.untyped])
              .returns(T.any(FeatureComparisonSubsection, ChatModels))
          end
          # rubocop:enable Sorbet/ForbidTUntyped
          private_class_method def self.map_comparison_feature_or_models(feature)
            title = extract_rich_text(feature["heading"])

            # Check if this is a chat models section by title or by presence of model fields
            if chat_models_feature?(title, feature)
              map_chat_models_feature(title, feature)
            else
              map_comparison_feature(feature)
            end
          end

          # Check if a feature should be mapped as chat models
          sig { params(title: String, feature: T::Hash[String, T.untyped]).returns(T::Boolean) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.chat_models_feature?(title, feature)
            title_lower = title.downcase
            return true if CHAT_MODELS_TITLES.any? { |t| title_lower.include?(t) }
            return true if feature.keys.any? { |k| k.to_s.include?("models_for_") }

            # Check if custom_text contains unordered-list (model lists)
            custom_text = feature["custom_text_for_free"]
            if custom_text.is_a?(Hash)
              content = custom_text["content"]
              return content.respond_to?(:any?) && content.any? { |c| c["nodeType"] == "unordered-list" }
            end

            false
          end

          # Map a feature to ChatModels
          sig { params(title: String, feature: T::Hash[String, T.untyped]).returns(ChatModels) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.map_chat_models_feature(title, feature)
            # First, extract all models for each plan
            all_models_by_plan = {}
            PLAN_IDS.each do |plan_id|
              models_key = plan_id == "pro_plus" ? "models_for_pro_plus" : "models_for_#{plan_id}"
              custom_text_key = plan_id == "pro_plus" ? "custom_text_for_pro_plus" : "custom_text_for_#{plan_id}"

              models_data = feature[models_key]
              all_models_by_plan[plan_id] = if models_data.is_a?(Array) && models_data.any?
                extract_models_list(models_data)
              else
                extract_models_from_rich_text(feature[custom_text_key])
              end
            end

            # Now compute incremental models for each tier
            # Free: all models for free
            # Pro: models in pro that are NOT in free
            # Pro+: models in pro_plus that are NOT in pro
            free_model_titles = Set.new(all_models_by_plan["free"].map(&:title))
            pro_model_titles = Set.new(all_models_by_plan["pro"].map(&:title))

            incremental_models = {
              "free" => all_models_by_plan["free"],
              "pro" => all_models_by_plan["pro"].reject { |m| free_model_titles.include?(m.title) },
              "pro_plus" => all_models_by_plan["pro_plus"].reject { |m| pro_model_titles.include?(m.title) }
            }

            plans = PLAN_IDS.map do |plan_id|
              plan_title = build_chat_model_plan_title(plan_id)

              ChatModelPlan.new(
                copilot_license_type: title_to_license_type(plan_id_to_title(plan_id)),
                title: plan_title,
                models: incremental_models[plan_id]
              )
            end

            ChatModels.new(
              title: title,
              plans: plans
            )
          end

          # Extract models from rich text unordered list (only non-strikethrough items)
          sig { params(rich_text: T.untyped).returns(T::Array[ChatModel]) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.extract_models_from_rich_text(rich_text)
            return [] unless rich_text.is_a?(Hash)

            content = rich_text["content"]
            return [] unless content.is_a?(Array)

            models = []
            content.each do |node|
              next unless node["nodeType"] == "unordered-list"

              list_items = node["content"] || []
              list_items.each do |item|
                next unless item["nodeType"] == "list-item"

                # Extract text and check for strikethrough
                model_info = extract_list_item_text_and_marks(item)
                next if model_info[:strikethrough] || model_info[:text].blank?

                models << ChatModel.new(title: model_info[:text])
              end
            end

            models
          end

          # Extract text and marks from a list item
          sig { params(item: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.extract_list_item_text_and_marks(item)
            text_parts = T.let([], T::Array[String])
            has_strikethrough = T.let(false, T::Boolean)

            traverse_nodes = T.let(nil, T.nilable(T.proc.params(nodes: T.untyped).void)) # rubocop:todo Sorbet/ForbidTUntyped
            traverse_nodes = lambda do |nodes|
              next unless nodes.is_a?(Array)

              nodes.each do |node|
                if node["nodeType"] == "text"
                  text_parts << node["value"].to_s
                  marks = node["marks"] || []
                  has_strikethrough = true if marks.any? { |m| m["type"] == "strikethrough" }
                elsif node["content"]
                  traverse_nodes&.call(node["content"])
                end
              end
            end

            traverse_nodes.call(item["content"])

            { text: text_parts.join, strikethrough: has_strikethrough }
          end

          # Extract models list from Contentful data
          sig { params(models_data: T.untyped).returns(T::Array[ChatModel]) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.extract_models_list(models_data)
            return [] unless models_data.is_a?(Array)

            models_data.filter_map do |model|
              model_title = if model.is_a?(Hash)
                title_text = extract_rich_text(model["title"])
                title_text = extract_rich_text(model["heading"]) if title_text.blank?
                title_text = model["name"].to_s if title_text.blank?
                title_text
              else
                model.to_s
              end

              next if model_title.blank?

              ChatModel.new(title: model_title)
            end
          end

          # Build the plan title for chat models (e.g., "Pro · Every model in Free and:")
          sig { params(plan_id: String).returns(String) }
          private_class_method def self.build_chat_model_plan_title(plan_id)
            case plan_id
            when "free"
              "Free"
            when "pro"
              "Pro · Every model in Free and:"
            when "pro_plus"
              "Pro+ · Every model in Pro and:"
            else
              plan_id_to_title(plan_id)
            end
          end

          sig { params(feature: T::Hash[String, T.untyped]).returns(FeatureComparisonSubsection) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.map_comparison_feature(feature)
            title = extract_rich_text(feature["heading"])

            # Build plan rows from status_for_* and custom_text_for_* fields
            plan_rows = PLAN_IDS.map do |plan_id|
              status_key = plan_id == "pro_plus" ? "status_for_pro_plus" : "status_for_#{plan_id}"
              custom_text_key = plan_id == "pro_plus" ? "custom_text_for_pro_plus" : "custom_text_for_#{plan_id}"

              status = feature[status_key]
              custom_text = feature[custom_text_key]
              subtitle = custom_text.is_a?(Hash) ? extract_rich_text(custom_text) : custom_text&.to_s

              # Determine icon - check for "unlimited" in subtitle text
              # Fallback to "none" to match Platform::Enums::MobileCopilotPaywallIcon
              icon = if subtitle&.downcase&.include?("unlimited")
                "unlimited"
              else
                STATUS_TO_ICON[status] || "none"
              end

              FeatureComparisonSubsectionItem.new(
                copilot_license_type: title_to_license_type(plan_id_to_title(plan_id)),
                plan_title: plan_id_to_title(plan_id),
                icon: icon,
                subtitle: subtitle.presence
              )
            end

            FeatureComparisonSubsection.new(
              title:,
              plan_rows:
            )
          end

          # Extract plain text from Contentful rich text structure
          sig { params(rich_text: T.untyped).returns(String) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.extract_rich_text(rich_text)
            return "" if rich_text.nil?
            return rich_text.to_s unless rich_text.is_a?(Hash)

            content = rich_text["content"]
            return "" if content.nil?

            extract_text_from_nodes(content)
          end

          sig { params(nodes: T::Array[T.untyped]).returns(String) } # rubocop:todo Sorbet/ForbidTUntyped
          private_class_method def self.extract_text_from_nodes(nodes)
            result = nodes.map do |node|
              if node["nodeType"] == "text"
                node["value"].to_s
              elsif node["content"]
                extract_text_from_nodes(node["content"])
              else
                ""
              end
            end
            result.join
          end

          sig { params(title: String).returns(String) }
          private_class_method def self.title_to_license_type(title)
            case title.downcase
            when "free" then "copilot_free"
            when "pro" then "copilot_individual"
            when "pro+" then "copilot_individual_pro_plus"
            else "copilot_#{title.downcase.gsub(/\s+/, '_')}"
            end
          end

          sig { params(plan_id: String).returns(String) }
          private_class_method def self.plan_id_to_title(plan_id)
            case plan_id
            when "free" then "Free"
            when "pro" then "Pro"
            when "pro_plus" then "Pro+"
            else plan_id.titleize
            end
          end
        end
      end
    end
  end
end
