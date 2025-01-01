# typed: false
# frozen_string_literal: true

module Spam
  class ContentBasedClassifier
    MODEL_NAME_MAP = {
      "Gist": "gist",
      "Issue": "issue",
      "IssueComment": "issue_comment",
      "PullRequestReviewComment": "issue_comment",
      "CommitComment": "issue_comment",
      "GistComment": "gist_comment",
    }

    def classify(html:, model_name: nil, requester: nil)
      classifier_model_name = MODEL_NAME_MAP[model_name.to_sym]

      if classifier_model_name.nil?
        Spam.stats_increment("content_based_classifier.unknown_model", tags: ["model_name:#{model_name}"])
        classifier_model_name = "issue_comment"
      else
        Spam.stats_increment("content_based_classifier.classify", tags: [
          "model_name:#{model_name}",
          "classifier:#{classifier_model_name}",
        ])
      end

      content_based_classifier_request(
        path: "/v1/predict?model=#{classifier_model_name}",
        body: GitHub::JSON.encode({ html: html }),
        fallback: { "spam" => 0.5, "ham" => 0.5 },
      )
    end

    EXCEPTION_TIME_FRAME = 10.seconds
    MAX_ALLOWED_EXCEPTIONS = 80
    MAX_ALLOWED_RETRIES = 3
    OPEN_TIMEOUT = 3 # seconds
    CONNECTION_TIMEOUT = 6 # seconds
    SETTINGS_URL = "https://github.com/devtools/spamurai/settings"

    # Internal: Make request and return parsed response. Disable if more than
    # MAX_ALLOWED_EXCEPTIONS occur in EXCEPTION_TIME_FRAME.
    #
    # path: String uri path.
    # body: String request body.
    # fallback: Optional value to return in exceptional circumstances.
    #
    # Returns parsed response.
    def content_based_classifier_request(path:, body: nil, fallback: nil)
      begin
        retries ||= 0
        tags = ["path:#{path}"]

        response = Spam.stats_time("content_based_classifier.request", tags: tags) do
          connection.post(path, body) do |request|
            request.options.open_timeout = OPEN_TIMEOUT
            request.options.timeout = CONNECTION_TIMEOUT
          end
        end

        Spam.stats_increment("content_based_classifier.response", tags: tags.concat(["status:#{response.status}"]))

        GitHub::JSON.parse(response.body)
      rescue Faraday::Error => error
        if (retries += 1) <= MAX_ALLOWED_RETRIES
          Spam.stats_increment("content_based_classifier.retry_request", tags: tags.concat(["retry_count:#{retries}"]))
          retry
        end
        circuit_breaker(error)
        fallback
      rescue Yajl::ParseError => error
        circuit_breaker(error)
        fallback
      end
    end

    # Internal: Disable.
    def disable!
      Spam.disable_spamurai
    end

    def enabled?
      Spam.spamurai_enabled?
    end

    # Internal: Faraday connection.
    #
    # Returns a Faraday::Connection.
    def connection
      @connection ||= Faraday.new(url: URL, headers: headers) do |faraday|
        faraday.adapter(Faraday.default_adapter)
      end
    end

    def headers
      { "Content-Type" => "application/json" }
    end

    URL = "https://content-based-classifier-production.service.iad.github.net/"

    # Internal: Send message to interested chat rooms.
    def notify_in_chat(message)
      Spam.notify(channel: "platform-health-ops", message: message)
    end

    ERROR_COUNTER_KEY = "content-based-classifier-error-count"

    # Internal: The number of errors that have occurred in the past 10 seconds.
    #
    # Returns an Integer.
    def error_count
      Spam::Kv.store.get(ERROR_COUNTER_KEY).value { 0 }.to_i
    end

    # Internal: Update error count and set it to expire in 10 seconds.
    #
    # error_count - Integer.
    def update_error_count(error_count)
      Spam::Kv.store.set ERROR_COUNTER_KEY,
        error_count.to_s,
        expires: EXCEPTION_TIME_FRAME.from_now
    end

    # Internal: Break circuit if enabled and enough errors happen in time window.
    def circuit_breaker(error)
      updated_error_count = error_count + 1

      update_error_count(updated_error_count)

      if enabled?
        Failbot.report(error, current_error_count: updated_error_count)

        if updated_error_count > MAX_ALLOWED_EXCEPTIONS
          disable!
          notify_in_chat [
            "Disabled content-based-classifier (#{error.message})",
            SETTINGS_URL,
            "/cc @erebor @hktouw @jonmagic @spicycode",
          ].join("\n")
        end
      end
    end
  end
end
