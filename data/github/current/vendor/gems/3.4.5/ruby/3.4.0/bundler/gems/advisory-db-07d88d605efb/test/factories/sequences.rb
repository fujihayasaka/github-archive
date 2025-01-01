# frozen_string_literal: true

FactoryBot.define do
  sequence :id, 1

  sequence :ghsa_id do
    GHSAIDGenerator.generate_ghsa_id
  end

  sequence :cve_id do |number|
    "CVE-#{Date.current.year}-#{number.to_s.rjust(4, "0")}"
  end

  sequence :cwe_id, "CWE-1"

  sequence :white_source_id do |number|
    "WS-#{Date.current.year}-#{number.to_s.rjust(4, "0")}"
  end

  sequence :severity do |number|
    AdvisoryDB.severities.fetch(number % AdvisoryDB.severities.count)
  end

  sequence :source do |number|
    index = number % AdvisoryDB.sources.count
    # malware_advisory & advisory_improvement feeds are curated differently from other sources,
    # so unless tests explicitly set it, let's assume we want a typical feed
    # cve_review programmatically impacts concepts of "open"ness of review, leave it out too.
    index = 0 if ["malware_advisory", "advisory_improvement", "cve_review"].include?(AdvisoryDB.sources[index])
    AdvisoryDB.sources.fetch(index)
  end

  sequence :url do
    Faker::Internet.url
  end

  sequence :ecosystem do |number|
    index = number % AdvisoryDB.curator_publishable_ecosystems.count
    AdvisoryDB.curator_publishable_ecosystems.fetch(index)
  end

  sequence :package_name do
    name = "#{Faker::Color.color_name.titleize} #{Faker::Creature::Dog.name}"
      .parameterize(preserve_case: rand(4).zero?)
      .tr("-", "_")

    case rand(3)
    when 0 then name              # foo_bar, Foo_Bar
    when 1 then name.tr("_", "-") # foo-bar, Foo-Bar
    when 2 then name.classify     # FooBar
    end
  end

  sequence :maven_package_name do
    group_id = Faker::Internet.domain_name.split(".").reverse.join(".")
    artifact_id = FactoryBot.generate(:package_name)
    "#{group_id}:#{artifact_id}"
  end

  sequence :version, "0.1.0"

  sequence :version_range do
    versions = FactoryBot.generate_list(:version, rand(2..11))
    ">= #{versions.first}, < #{versions.last}" # >= 1.2.3, <= 1.2.4
  end

  sequence :slack_message_ts do
    Time.current.to_f.round(6).to_s
  end

  sequence :github_access_token do
    "v1.deadbeef#{SecureRandom.hex}"
  end

  sequence :git_sha do
    SecureRandom.hex(20)
  end

  sequence :node_id do
    Base64.strict_encode64(SecureRandom.uuid)
  end
end
