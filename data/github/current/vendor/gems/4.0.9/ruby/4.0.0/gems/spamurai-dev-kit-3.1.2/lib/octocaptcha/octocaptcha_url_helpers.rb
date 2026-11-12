module SpamuraiDevKit
  module OctocaptchaUrlHelpers
    def host_name
      if is_production_env? || is_staging_env?
        "octocaptcha.com".freeze
      else
        "octocaptcha.localhost".freeze
      end
    end

    def url
      if is_production_env? || is_staging_env?
        "https://#{host_name}".freeze
      else
        "http://#{host_name}".freeze
      end
    end

    def origin_page
      "#{app_name}_#{feature_name}".gsub("-", "_")
    end

    # Generates octocaptcha iframe url
    # origin_url - the url of your website. ex enterprise.github.com
    #   Defaults to app_url configuration
    # origin_page - name of your page. defaults to app_name + feature name
    def url_for_iframe(
      origin_url: app_url,
      origin_page: self.origin_page,
      responsive: true,
      nojs: false
    )
      octocaptcha_params = ["origin=#{origin_url}"]

      octocaptcha_params << if is_production_env? || is_staging_env?
        "origin_page=#{origin_page}"
      else
        "origin_page=localhost"
      end

      octocaptcha_params << "responsive=true" if responsive
      octocaptcha_params << "nojs=true" if nojs

      "#{url}?#{octocaptcha_params.join("&")}"
    end

    # Generates DataDome-dedicated iframe URL (points to /datadome endpoint)
    def datadome_url_for_iframe(origin_page = nil)
      return nil unless datadome_captcha_enabled?
      uri = URI(url)
      uri.path = "/datadome"
      params = { origin: app_url }
      params[:origin_page] = origin_page || self.origin_page
      uri.query = URI.encode_www_form(params)
      uri.to_s
    end

    # Check if DataDome captcha is enabled (calls the lambda)
    def datadome_captcha_enabled?
      use_datadome&.call == true
    end
  end
end
