require Rails.root.join("spec/support/package_factory")

def gemspec(package_name, version, attrs = {})
  package_attrs = attrs.slice(:repository_id)
  version_attrs = attrs.reverse_merge(published_at: Time.now)
  PackageFactory.new(package_name, version)
    .tap { |factory| factory.create(version_attrs, package_attrs) }
end

gemspec("rake", "11.2.2", repository_id: 20037550)

gemspec("multi_xml", "0.5.5", repository_id: 957805)
  .dependency("rake", "")

gemspec("fakeweb", "1.3.0", repository_id: 62360)
  .dependency("rake", "~> 0")

gemspec("daemons", "1.0.3", repository_id: 18698925)

gemspec("mongrel", "1.3.0", repository_id: 38111)
  .dependency("daemons", "1.0.3")

gemspec("httparty", "0.14.0", repository_id: 37997)
  .dependency("multi_xml", ">= 0.5.2")
  .dependency("rake", "")
  .dependency("fakeweb", "~> 1.3")
  .dependency("mongrel", ">= 1.2.0")
