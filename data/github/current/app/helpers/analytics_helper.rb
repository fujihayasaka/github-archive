# typed: true
# frozen_string_literal: true

module AnalyticsHelper
  include HydroHelper
  EVENT_RESERVED_CHARACTERS = %r([,'"])

  def safe_analytics_click_attributes(category:, action:, label: nil, **context)
    analytics_attributes = analytics_click_attributes(
      **T.unsafe({
        category: category,
        action: action,
        label: label,
        **context
      }),
    )

    safe_data_attributes(analytics_attributes)
  end

  def analytics_click_attributes(category:, action:, label: nil, **context)
    {
      "analytics-event" => JSON.generate({
        category: category,
        action: action,
        label: label,
        **context,
      })
    }
  end

  def safe_analytics_click_attrs_marketing(action:, tag:, context:, location:)
    analytics_attributes = analytics_click_attrs_marketing(
      action: action,
      tag: tag,
      context: context,
      location: location,
    )
    safe_data_attributes(analytics_attributes)
  end

  def analytics_click_attrs_marketing(action:, tag:, context:, location:)
    {
      "analytics-event" => JSON.generate({
        location: location,
        action: action,
        context: context,
        tag: tag,
        label: "#{action}_#{tag}_#{context}_#{location}",
      })
    }
  end

  def analytics_visible_attributes(category:, text: nil, **context)
    {
      "analytics-visible" => JSON.generate({
        category: category,
        action: "visible",
        label: "text: #{text}",
        **context,
      })
    }
  end

  def analytics_visible_data_attributes(category:, text: nil, **context)
    safe_data_attributes({
      "analytics-visible" => JSON.generate({
        category: category,
        action: "visible",
        label: "text: #{text}",
        **context,
      })
    })
  end

  def sanitized_ga_params(category:, action:, label: "")
    category = category.dup.gsub(EVENT_RESERVED_CHARACTERS, "")
    action = action.dup.gsub(EVENT_RESERVED_CHARACTERS, "")
    label = label.dup.gsub(EVENT_RESERVED_CHARACTERS, "")

    [category, action, label].join(", ")
  end

  def analytics_account_prefix(account)
    @analytics_prefix ||= account.organization? ? "Org" : "User"
  end
end
