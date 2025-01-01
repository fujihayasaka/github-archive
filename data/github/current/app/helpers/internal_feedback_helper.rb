# typed: false
# frozen_string_literal: true

module InternalFeedbackHelper
  DESIRED_HEADER_KEYS = %w[
    REMOTE_ADDR
    HTTP_HOST
    HTTP_X_NGINX_REQUEST_START
    HTTP_CONNECTION
    HTTP_SEC_CH_UA
    HTTP_USER_AGENT
    HTTP_SEC_CH_UA_MOBILE
    HTTP_SEC_FETCH_SIT
    HTTP_SEC_FETCH_MODE
    HTTP_REFERER
    HTTP_ACCEPT
    HTTP_ACCEPT_ENCODING
    HTTP_ACCEPT_LANGUAGE
    SERVER_SOFTWARE
    SERVER_NAME
  ].freeze

  def json_headers_for_feedback(headers)
    headers.to_h.slice(*DESIRED_HEADER_KEYS).to_json
  end

  def features_list_for_feedback
    flipper_features = FlipperSubscriber.tested_features.keys
    vexi_features = VexiSubscriber.tested_features.keys

    combined_features = (flipper_features + vexi_features).uniq

    combined_features.partition do |feature|
      FlipperSubscriber.tested_features[feature] || VexiSubscriber.tested_features[feature]
    end
  end

  def find_feedback_recipient_info_by_name(name)
    return unless org = Organization.find_by_login("github")
    [org.find_repo_by_name(name), nil]
  end

  def find_feedback_recipient_info_from_ownership_doc(logical_service_name)
    return unless org = Organization.find_by_login("github")

    ownership_info = get_info_from_ownership_yaml(logical_service_name)
    repo = get_repo_from_info(org, ownership_info)
    team = ownership_info&.fetch("team", nil)

    return [repo, team] if repo&.private?
    [org.find_repo_by_name("github"), team]
  end

  private

  def get_info_from_ownership_yaml(logical_service_name)
    ownership_yaml_path = Rails.root.join("ownership.yaml")
    ownerships = YAML.safe_load(ownership_yaml_path.read)
    ownerships["ownership"].find { |h| h["name"] == logical_service_name }
  end

  def get_repo_from_info(org, info)
    return unless info

    repo_url = info["repo"]
    repo_name = repo_url.gsub("https://github.com/github/", "")
    org.find_repo_by_name(repo_name)
  end

  def format_extra_data(referrer, params, team_name)
    <<~MD


    #{"/cc @#{team_name}" if team_name}

    ---

    Referrer: #{referrer}
    Branch: [#{params[:branch]}](https://github.com/github/github/tree/#{params[:branch]})
    SHA: [#{params[:sha]&.slice(0, 7)}](https://github.com/github/github/commit/#{params[:sha]})
    [Flamegraph](#{params[:flamegraph_url]})
    Rails version: #{params[:rails_version]}
    Ruby version: #{RUBY_VERSION}

    <details>
    <summary>Stats</summary>
    <p>

    Response time: #{params[:response_time_stats]}
    CPU stats: #{params[:cpu]}
    GC: #{params[:gc]}
    ES loader: #{params[:es_loader_stats]}
    ES: #{params[:es_stats]}
    Render time: #{params[:render_time]}
    Redis: #{params[:redis]}
    Cache: #{params[:cache]}
    Geyser: #{params[:geyser]}
    GraphQL: #{params[:graphql]}
    GitRPC: #{params[:gitrpc]}

    </p>
    </details>

    <details>
    <summary>Headers</summary>
    <p>

    ```
    #{header_info(params[:captured_headers])}
    ```

    </p>
    </details>

    <details>
    <summary>Feature Flags</summary>
    <p>

    ## Enabled Features

    #{features_flags_info(params[:enabled_features])}

    ## Disabled Features
    #{features_flags_info(params[:disabled_features])}

    </p>
    </details>

    MD
  end

  def features_flags_info(features)
    (features || "")
      .split
      .map { |feature| "[#{feature}](#{devtools_feature_flag_path(feature)})" }
      .join("\n")
  end

  def header_info(captured_headers)
    return "" if captured_headers.blank?
    JSON.parse(captured_headers)
      .map { |k, v| "#{k}: #{v}" }
      .join("\n")
  end
end
