# typed: true
# frozen_string_literal: true

class ApiRoutes::ASTEndpoint
  include Comparable

  VERB_ORDER = [:get, :post, :put, :patch, :delete]

  def self.from(namespace, verb, route, body, file_path, node)
    new(verb, route, access_controls(body), namespace, body.loc.line, docs_url(body), file_path, operation_ids(node))
  end

  def self.docs_url(root)
    return nil if root.children.empty?
    return nil unless root.is_a?(RuboCop::AST::Node)

    if root.ivasgn_type? && root.children.first == :"@documentation_url"
      node = root.children.last
      if node.children.count == 1
        return root.children.last.children.last
      end
      # If debugging, return node.to_s here.
      return
    end

    root.child_nodes.each do |child|
      url = docs_url(child)
      return url unless url.nil?
    end
    nil
  end

  def self.access_controls(root)
    return [] if root.is_a?(Symbol)
    # Temporarily special-case this access-control experiment so we detect calls in closures passed to it
    return [] if root.send_type?
    return [] if root.children.empty?
    controls = root.child_nodes.select do |child|
      child.send_type? && child.method_name == :control_access
    end
    root.child_nodes.each do |child|
      controls += access_controls(child)
    end
    controls
  end

  def self.operation_ids(root)
    single_value = RuboCop::NodePattern.new("`(hash <(pair (sym :operation_id) ({ str | sym } $_)) ...>)").match(root)
    return [single_value] if single_value

    RuboCop::NodePattern.new("`(hash <(pair (sym :operation_ids) (array $...)) ...>)").match(root)&.map(&:value)
  end

  attr_reader :source_url, :verb, :route, :control_accesses, :docs_url, :raw_route
  attr_reader :permissions, :operation_ids

  def initialize(verb, route, control_accesses, namespace, line, docs_url, file_path, operation_ids)
    # TODO: use the SHA1 instead of master
    # Note: the AST source line appears to be off-by-one
    @source_url = "https://github.com/github/github/blob/master#{file_path}#L%d" % (line - 1)
    @verb = verb
    @raw_route = route
    # If the route is defined using a regex rather than a string, we
    # need to normalize it to match the human-readable format that is
    # used in ApiRoutes::Endpoint.
    @route = route.
      gsub("*", "(.*?)").
      gsub("(d+)", "(\\d+)").
      gsub("(.+)", "(.+))"). # temporary: work around a bug in the rake task cleanup
      gsub("(.(.*?))", "(.*)").
      gsub(/^\^/, "").
      gsub(/\$$/, "")
    @control_accesses = control_accesses
    @operation_ids = operation_ids

    @docs_url = docs_url
    if docs_url == "/v3/repos/contents/#update-a-file" && verb == :delete
      @docs_url = @docs_url.gsub("update", "delete")
    end
  end

  # The permissions for projects are quite tangled. Sorry.
  def permissions=(perms)
    perms = perms.dup
    perms.delete("repository_projects") if route.include?("organizations")
    perms.delete("organization_projects") if route.include?("repositories")
    @permissions = perms
  end

  def subgroup
    %w(branches requested_reviewers import traffic git keys invitations collaborators milestones comments labels assignees reactions teams members events reviews releases).find do |group|
      Regexp.new("\/#{group}").match route
    end || ""
  end

  def to_s
    "%s %s" % [verb.to_s.upcase, route]
  end

  def to_docstyle
    "%s %s" % [verb.to_s.upcase, docstyle_route]
  end

  def docstyle_route
    @docstyle_route ||= docstyle_route_replacements.reduce(route) do |s, (k, v)|
      s.gsub(k, v)
    end
  end

  def docstyle_route_replacements
    {
      "/branches/(.*?)"                 => "/branches/:branch",
      "/cards/:id"                      => "/cards/:card_id",
      "/collaborators/:collab"          => "/collaborators/:username",
      "/columns/:id"                    => "/columns/:column_id",
      "/commits/(.*?)"                  => "/commits/:sha",
      "/commits/:id"                    => "/commits/:sha",
      "/compare/(.*?)"                  => "/compare/:base...:head",
      "/contents/(.+))"                 => "/contents/:path",
      "/contents/?(.*?)"                => "/contents/:path",
      "/deployments/:deployment_id"     => "/deployments/:id",
      "/issues/:id"                     => "/issues/:number",
      "/labels/(.*?)"                   => "/labels/:name",
      "/members/:user"                  => "/members/:username",
      "/memberships/:user"              => "/memberships/:username",
      "/milestones/:id"                 => "/milestones/:number",
      "/organizations/:organization_id" => "/orgs/:org",
      "/outside_collaborators/:user"    => "/outside_collaborators/:username",
      "/projects/:id"                   => "/projects/:project_id",
      "/pulls/:id"                      => "/pulls/:number",
      "/readme(?:/(.*))?"               => "/readme",
      "/refs/(.*?)"                     => "/refs/:ref",
      "/repositories/(\\d+)"            => "/repos/:owner/:repo",
      "/repositories/:repository_id"    => "/repos/:owner/:repo",
      "/status/(.*?)"                   => "/commits/:ref/status",
      "/statuses/(.*?)"                 => "/commits/:ref/statuses",
      "/tags/(.*?)"                     => "/tags/:tag",
      "/tags/:id"                       => "/tags/:sha",
      "/tarball/?(.*?)?"                => "/:archive_format/:ref",
      "/trees/(.*?)"                    => "/trees/:sha",
      "/user/:user_id"                  => "/users/:username",
      "/zipball/?(.*?)?"                => "/:archive_format/:ref",
    }
  end

  def docs_description
    doc_description_replacements.reduce(docs_url.to_s.gsub(/.*#/, "").gsub("-", " ")) do |s, (k, v)|
      s.gsub(k, v)
    end
  end

  def doc_description_replacements
    {
      "get a users marketplace purchases" => "get a user's Marketplace purchases",
      "youve" => "you've",
      "a users" => "a user's",
    }
  end

  def <=>(other)
    comp = route <=> other.route
    comp.zero? ? VERB_ORDER.index(verb) <=> VERB_ORDER.index(other.verb) : comp
  end

  # We have a number of inconsistencies between the API and the documentation
  # that we try to work around here with hacky object equality.
  #
  # In particular, we define both POST and PATCH (and occasionally PUT) for some endpoints,
  # but document only PATCH.

  def eql?(other)
    normalized_docstyle_inspect == other.normalized_docstyle_inspect
  end

  def ==(other)
    normalized_docstyle_inspect == other.normalized_docstyle_inspect
  end

  def hash
    potential_canonical_verb.to_s.hash ^ docstyle_route.hash ^ docs_url.hash
  end

  # If we want to uniq such that patch is first, we need
  # a custom order before calling uniq.
  def verb_priority
    [:get, :patch, :post, :put, :delete].index(verb)
  end

  def control_access_calls
    @control_access_calls ||= control_accesses.map do |control_access|
      defn = ApiRoutes::ControlAccessCall.new(control_access.arguments.first.children.first)

      context = control_access.arguments.find(&:hash_type?)
      context && context.children.each do |child|
        k, v = child.children
        key = k.children.first
        if [:allow_integrations, :allow_user_via_granular_actor].include?(key)
          defn.set(k.children.first, v.true_type? ? true : false)
        end
      end
      defn
    end
  end

  def disabled?
    audited? && !enabled_for_integrations? && !enabled_for_user_via_integrations?
  end

  def audited?
    !control_access_calls.empty? && control_access_calls.all?(&:audited?)
  end

  def enabled?
    enabled_for_integrations? || enabled_for_user_via_integrations?
  end

  def enabled_for_integrations?
    !server_to_server_permissions.empty? && server_to_server_permissions.all?
  end

  def enabled_for_user_via_integrations?
    !user_to_server_permissions.empty? && user_to_server_permissions.all?
  end

  def user_to_server_permissions
    @user_to_server_permissions ||= control_access_calls.map(&:u2s?).compact
  end

  def server_to_server_permissions
    @server_to_server_permissions ||= control_access_calls.map(&:s2s?).compact
  end

  protected

  def normalized_docstyle_inspect
    @normalized_docstyle_inspect ||= "%s %s (%s)" % [potential_canonical_verb.to_s.upcase, docstyle_route, docs_url]
  end

  def potential_canonical_verb
    { post: :patch, put: :patch }[verb] || verb
  end
end
