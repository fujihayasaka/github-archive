module JsonHelpers
  module_function

  def parse_json_response!(response)
    content_type = response.headers["Content-Type"].to_s
    body = response.body.to_s

    unless content_type.include?("application/json")
      raise <<~MSG
        Expected JSON response but got Content-Type=#{content_type.inspect}
        Body starts with: #{body[0, 300].inspect}
      MSG
    end

    JSON.parse(body)
  rescue JSON::ParserError => e
    raise <<~MSG
      Failed to parse JSON: #{e.message}
      Content-Type=#{content_type.inspect}
      Body starts with: #{body[0, 300].inspect}
    MSG
  end
end
