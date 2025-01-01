# frozen_string_literal: true

if defined? RubyVM::YJIT.enable
  # Similar but slightly different to "prefix environment". This allows
  # enabling YJIT for a percentage of unicorns and configuring that by role,
  # site, and kube cluster.
  #
  # Examples:
  #   GH_YJIT_ENABLE_PCT=100 (fully enabled)
  #   GH_YJIT_ENABLE_PCT=50 (50% on all frontend unicorns)
  #   GH_YJIT_ENABLE_PCT_FE_ASH1_IAD=50 (50% on dotcom1-ash1-iad frontend unicorns)
  #   GH_YJIT_ENABLE_PCT_FE_DOTCOM_1_ASH1_IAD=50 (50% on dotcom1-ash1-iad frontend unicorns)

  env_keys = ["GH_YJIT_ENABLE_PCT"]
  env_keys += env_keys.map { |x| "#{x}_#{GitHub.role}" }
  env_keys += env_keys.map { |x| "#{x}_#{GitHub.site}" }
  env_keys += env_keys.map { |x| "#{x}_#{GitHub.kubernetes_cluster_name}" } if GitHub.kubernetes_cluster_name

  env_keys.map! { |x| x.upcase.tr("-", "_") }

  enabled_pct = nil
  env_keys.reverse_each do |key|
    enabled_pct ||= ENV[key]
  end
  enabled_pct ||= 0

  if rand < (enabled_pct.to_f / 100.0)
    Rails.application.config.after_initialize do
      RubyVM::YJIT.enable
    end
  end
end
