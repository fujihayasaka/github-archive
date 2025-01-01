# typed: true
# frozen_string_literal: true

module GitAuth
  autoload :Access, "git_auth/access"
  autoload :Authorization, "git_auth/authorization"
  autoload :CommitRefs, "git_auth/commit_refs"
  autoload :CommitRefsRequestBody, "git_auth/commit_refs_request_body"
  autoload :ConditionalAccessDependency, "git_auth/conditional_access_dependency"
  autoload :Failure, "git_auth/failure"
  autoload :Gist, "git_auth/gist"
  autoload :GitLFS, "git_auth/git_lfs"
  autoload :HydroPublisher, "git_auth/hydro_publisher"
  autoload :Login, "git_auth/login"
  autoload :Metrics, "git_auth/metrics"
  autoload :Pipeline, "git_auth/pipeline"
  autoload :Ref, "git_auth/ref"
  autoload :Refs, "git_auth/refs"
  autoload :SSHCertificateAuthority, "git_auth/ssh_certificate_authority"
  autoload :SSHKey, "git_auth/ssh_key"
  autoload :SSHLoginParser, "git_auth/ssh_login_parser"
  autoload :SpokesdListRoutes, "git_auth/spokesd_list_routes"
  autoload :Target, "git_auth/target"
  autoload :PushHandler, "git_auth/push_handler"
  autoload :PushNotices, "git_auth/push_notices"
end
