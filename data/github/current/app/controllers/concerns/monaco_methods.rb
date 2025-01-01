# typed: true
# frozen_string_literal: true

module MonacoMethods
  def monaco_worker_paths(web_worker_url)
    types = %w[editor css html json ts]
    types.each_with_object({}) do |type, hash|
      hash[type.to_sym] = web_worker_url.call("monaco-#{type}-worker.js")
    end
  end
end
