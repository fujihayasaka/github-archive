# typed: true
# frozen_string_literal: true

module Site
  module PreserveTrackingParamsDependency
    extend T::Helpers
    include GitHub::Memoizer

    requires_ancestor { ApplicationController }

    def preserve_tracking_params_path(to_path, additional_params = {})
      params = tracking_params.merge(additional_params)
      return to_path if params.empty?

      uri = URI::HTTP.build(path: to_path, query: params.to_query)
      # only return the absolute path and query, don't include blank hostname and protocol
      "#{uri.path}?#{uri.query}"
    end

    memoize def tracking_params
      tracked_utm_params.merge(tracked_funnel_params)
    end

    def tracked_utm_params
      supported = %i(utm_source utm_medium utm_campaign utm_term utm_content)

      from_url = params.slice(*supported).permit!
      from_session = session.fetch(:utm_memo, {})

      from_session.merge(from_url).symbolize_keys
    end

    def tracked_funnel_params
      params.slice(:new_signup, :cft).permit!
    end
  end
end
