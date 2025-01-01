# typed: false
# frozen_string_literal: true

class Gist < ApplicationRecord::Domain::Gists
  include Configurable
  include Configurable::ArchiveResourceBlocking
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include GitHub::UTF8
  include GitHub::Validations
  include Gist::Backup
  include Gist::LegalHold
  include Gist::Maintenance
  include Gist::NewsiesAdapter
  include Gist::NotifydAdapter
  include Gist::Removal
  include Gist::SpokesAPI
  include Gist::Quota
  include Gist::DGit
  include TreeListable
  include Entity
  include GitRepository::UrlMethods
  include GitRepository::SpokesAdapter
  include Instrumentation::Model
  include Spam::Spammable
  include GitHub::RateLimitedCreation
  include AbuseReportable
  include Starrable
  include UploadContainer::GistDependency

  MAINTENANCE_STATUSES = %w[scheduled running complete failed spurious_failure retry broken]

  # Used by the Discover/Forked/Starred and API to cap total results returned
  MAX_PUBLIC_GISTS_TO_PAGINATE = 3_000

  # The maximum number of files that we'll attemp to render in the UI and
  # API responses.
  # TODO: Enforce this at the git level.
  MAX_FILES = 300

  # The Integer size in bytes to limit indexed files. Files larger than this
  # will be truncated before indexing.
  MAX_INDEXABLE_BLOB_SIZE = 50_000

  # The Integer max number of files to index. Any files above this number will
  # be left out of the index.
  MAX_INDEXABLE_FILES = 40

  # The Ineger max number of bytes to test for binary determination.
  MAX_BINARY_TEST_SIZE = 4096

  # The Integer max number of lines to show in search results snippets.
  MAX_SNIPPET_LINES = 11

  MAX_DESCRIPTION_BYTESIZE = 1024

  MAX_GIST_TITLE_LENGTH = 250

  # The username for anonymous gists
  ANONYMOUS_USERNAME = "anonymous".freeze

  COMMENTS_PER_PAGE = 30

  belongs_to :user

  belongs_to :parent,
    -> { where(delete_flag: false) },
    class_name: "Gist"

  has_many :children,
    -> { where(delete_flag: false) },
    class_name: "Gist",
    foreign_key: :parent_id,
    inverse_of: :parent

  alias_method :forks, :children

  setup_spammable(:user)

  has_many :comments, class_name: "GistComment", dependent: :destroy, inverse_of: :gist

  # TODO: After the merge we're going to transition this table to the
  #       polymorphic stars model.
  has_many :stars, class_name: "GistStar"

  has_one :disabled_access_reason, as: :flagged_item

  alias_method       :owner, :user
  alias_method       :owner=, :user=

  scope :are_public,  -> { active.where(public: true) }
  scope :are_secret,  -> { active.where(public: false) }

  scope :owned,       -> { active.where("gists.user_id IS NOT NULL") }
  scope :anonymous,   -> { active.where("gists.user_id IS NULL") }
  scope :forks,       -> { active.where("gists.parent_id IS NOT NULL") }
  scope :from_ids,    -> (ids) { active.where(id: ids) }
  scope :most_recent, -> { order("gists.id DESC") }
  scope :since,       -> (time) { where("gists.updated_at >= ?", time) }
  scope :starred,     -> { active.where("gists.id IN (SELECT DISTINCT(gist_id) FROM starred_gists)") }

  scope :is_not_disabled, -> { active.where(disabled_at: nil) }

  # Use to filter gists that may come from multiple users for a given viewer.
  scope :filter_spam_and_disabled_for, ->(viewer) {
    relation = filter_spam_for(viewer)

    # Hide DMCA takedown gists from non-site-admins:
    relation = relation.is_not_disabled unless viewer&.site_admin?

    relation
  }

  # Use to filter one user's gists for a given viewer.
  scope :visible_to, -> (viewer, viewer_is_owner:, visibility:) {
    gists = filter_spam_for(viewer).is_not_disabled

    if visibility == "public" || !viewer_is_owner
      gists = gists.are_public
    elsif visibility == "secret"
      gists = gists.are_secret
    end

    gists
  }

  # This attr holds file contents from the Web/API.
  #
  # Expects an array of hashes like:
  #
  # [
  #   { :name => "filename1", :value => "content" },               # add
  #   { :name => "filename1", :value => "content", :oid => ".." }, # update
  #   { :name => "filename3", :value => "", :oid => ".." }         # delete
  # ]
  attr_accessor :contents

  # This attr holds the updating user from the Web/API.
  # If none is specified we fall back to using git_author
  attr_accessor :committing_user

  # preserve_line_endings allows us to programmatically control when we want to
  # replace \r\n with a simple newline \n character. We always want to perform this
  # replacement when a file is created via web form, and we never want to perform it
  # when a file is created or updated via the API.
  attr_accessor :preserve_line_endings

  def to_s
    repo_name
  end

  def to_param
    repo_name
  end

  # Sorted array of [filename, body] pairs from the `contents` hash.
  # Used for iterating over submitted contents after validation errors.
  def sorted_contents
    contents.to_a.sort_by { |(filename, _body)| self.class.normalize_for_sort(filename) }
  end

  validates_presence_of :user, on: :create,
    unless: proc { |_| GitHub.anonymous_gist_creation_enabled? }
  validates_presence_of :repo_name, on: :update
  validates :repo_name, unicode3: true
  validates :description, bytesize: { maximum: MAX_DESCRIPTION_BYTESIZE },
    unicode: true, allow_nil: true
  validate :ensure_user_has_verified_email, on: :create
  validate :ensure_valid_file_information
  validate :ensure_unique_filenames
  validate :ensure_no_subdirectories
  validate :ensure_files_present
  validate :ensure_files_have_content
  validate :ensure_file_contents_are_strings
  validate :ensure_valid_paths
  validate :ensure_user_not_trade_restricted_for_secret, on: :create
  # The maintenance_status attribute is used to track maintenance job runs.
  # Possible values are:
  #
  # scheduled - maintenance job has been scheduled but is not yet running.
  # running   - maintenance job is running on a worker.
  # complete  - maintenance job completed successfully.
  # failed    - maintenance job failed.
  # retry     - maintenance job failed because of an error that we deem
  #             recoverable, so we can retry it
  # broken    - the gist is broken and cannot be recovered,
  #             so further maintenance jobs should not be attempted
  #
  # May also be nil, in which case maintenance has never been performed for the
  # gist.
  validates_inclusion_of :maintenance_status,
    in: MAINTENANCE_STATUSES,
    allow_nil: true

  before_validation :scrub_description

  before_create :set_default_values
  before_update :bump_updated_at, if: :contents
  before_update :commit_contents_callback, if: :contents
  before_update :prevent_public_gists_from_becoming_private, if: :will_save_change_to_public?

  after_commit :instrument_creation, on: :create
  after_commit :audit_visibility_change, if: :saved_change_to_public?, on: [:create, :update]
  after_commit :synchronize_search_index

  after_commit :delete_replicas_and_checksums_after_commit_on_destroy,
               on: :destroy
  after_commit :destroy_notification_dependents, on: :destroy

  after_create :store_creator_ip, if: :creator_ip
  after_commit :subscribe_author, on: :create

  after_commit :scan_for_tokens, on: :update

  def global_id
    repo_name
  end

  # Find the gist corresponding to the full shard path. This is
  # capable of locating gists organized in a sharded layout like
  # "/data/repositories/e/nw/e4/78/53/gist/<repo_name>.git"
  # (github.com) as well as repositories organized in a simple layout like
  # "/data/repositories/gist/<repo_name>.git".
  def self.with_path(path)
    repo_name = File.basename(path, ".git")
    find_by_repo_name repo_name
  end

  # Public: Finds a gist given an name with owner
  #
  # owner     - The String login of the gist owner
  #             OR the full NWO string if repo_name is omitted.
  # repo_name - (optional) The String repo name for the Gist.
  #
  # Returns a Gist or nil if not found
  def self.with_name_with_owner(owner, repo_name = nil, include_deleted_gists = false)
    owner, repo_name = owner.to_s.split("/") if repo_name.nil?
    return nil unless owner.present? && repo_name.present?
    if owner == ANONYMOUS_USERNAME
      if include_deleted_gists
        find_by(user_id: nil, repo_name: repo_name)
      else
        active.find_by(user_id: nil, repo_name: repo_name)
      end
    else
      owner_id = User.where(login: owner).limit(1).pluck(:id).first
      if include_deleted_gists
        owner_id && where(user_id: owner_id, repo_name: repo_name).first
      else
        owner_id && active.where(user_id: owner_id, repo_name: repo_name).first
      end
    end
  end

  # Public: The Default scope combo for any public Gist listing
  def self.public_listing
    active.are_public.not_spammy.owned
  end

  # Public: Used for pagination to retrieve the forked gist ids
  #
  # Paginationing forked gists is a two pass query
  def self.forked_gist_ids
    select("gists.parent_id").where("gists.parent_id IS NOT NULL")
  end

  # Generate a unique repo name for the gist
  #
  # Returns the a random sha string as the repo_name
  def self.generate_unique_repo_name
    begin
      name = random_sha
    end while repo_exists? name # rubocop:disable Lint/Loop
    name
  end

  def self.random_sha
    SecureRandom.hex(16)
  end

  def self.repo_exists?(repo_name)
    Gist.where(repo_name: repo_name).exists?
  end

  def self.find_for_session(session, options = {})
    ids = session.present? ? session.keys.sort : []
    ids.reverse.paginate(page: 1, per_page: options[:limit] || 30).tap do |gists|
      gists.replace where(id: gists).to_a unless gists.empty?
    end
  end

  # Public: Takes an array of files and returns a truncated list. If the
  # number of files exceeds the given limit, non-truncated files are returned
  # first.
  #
  # files - the files to truncate
  # limit - (optional) the maximum number of files to return.
  #
  # Returns a truncated Array of files.
  def self.limit_files(files, limit = MAX_FILES)
    prefer_untruncated = files.partition { |f| !f.truncated? }
    prefer_untruncated.flatten.first(limit)
  end

  # Public: Selects gists which have been modified since forking
  #
  # Returns an Array of Gists
  def self.modified
    scoped.select(&:modified?)
  end

  # Public: Selects gists which have not been modified since forking
  #
  # Returns an Array of Gists
  def self.stale
    scoped.reject(&:modified?)
  end

  # Public: Returns only forks which should be visible to parent gist viewers.
  # Excludes secret forks when the parent gist is public.
  #
  # Returns an Array of Gists.
  def visible_forks
    public? ? forks.are_public : forks
  end

  # Fork the gist to a new user
  #
  # Return self if the owning user tries to fork their own gist
  # Returns an existing fork if one exists for the given user
  # Creates a new fork if no fork exists for the given user
  def fork(new_user)
    return self if self.user == new_user

    existing_fork = forks.where(user_id: new_user).first
    return existing_fork if existing_fork

    fork_creator = Gist::Creator.new(user: new_user, parent: self)

    if fork_creator.create
      # bump updated_at
      self.touch

      GitHub.dogstats.increment("gist.forked")
    end

    fork_creator.gist
  end

  # Count the stars for a Gist.
  #
  # viewer - Current viewer of the Gist, nil/false for anonymous users.
  # filter_spam - Used to filter for spam or not, defaults to false
  # to keep behaviour from before refactor.
  #
  # Returns the number of stargazers for a given Gist.
  def stargazer_count(viewer = nil, filter_spam = false)
    stargazer_ids = stars.pluck(:user_id)

    relation = User.where(id: stargazer_ids)
    relation = relation.filter_spam_for(viewer) if filter_spam
    relation.count
  end

  # Public: Are all comments on this gist by the author? Used for spam checking.
  # Spammers like to post a single 'file' with the filename the same
  # as the contents of the spam file, then comment on their own Gist.
  #
  # Returns a boolean.
  def all_comments_by_author?
    comments.all? { |comment| comment.user_id == user_id }
  end

  batch_method(:comment_count) do |gists|
    comment_counts = GistComment.where(gist_id: gists.map(&:id)).group(:gist_id).count
    gists.index_with { |gist| comment_counts[gist.id] || 0 }
  end

  # Public: Would return the name of the database field used to store the gist's star count, if the table had one.
  # Overridden from Starrable.
  #
  # Returns nil.
  def stargazer_count_column
    nil
  end

  # We are re-using the star/stargazing infrastructure, but we
  # don't yet have a ca$he column.  TODO: This.
  def update_stargazer_count!
    touch
  end

  # Update a single file. Used for task list updates.
  #
  # Returns the new String OID.
  def update_file(blob_oid:, content:, user:, post_receive: false)
    target_file = files.find { |f| f.oid == blob_oid }
    return false unless target_file

    # Drop windows line endings
    content.gsub!("\r\n", "\n")

    commit = commits.create({ author: user, message: "" }, master_commit.oid) do |stage|
      stage.add target_file.path, content
    end

    ref = heads.find_or_build(gist_repo_default_branch).update(commit, user, post_receive: post_receive)
    touch

    updated_file = files(ref.target_oid).find { |f| f.name == target_file.name }
    updated_file.oid
  end

  # The name of the key used to store an anonymous Gist author's IP in GitHub::KV
  def creator_ip_key
    return unless persisted?
    "gist.anonymous_creator_ip.#{id}"
  end

  # Set the author's IP address so they can delete their anonymous Gist later
  def creator_ip=(ip_address)
    return if GitHub.enterprise?
    return unless anonymous?

    @creator_ip = ip_address
  end

  # Retrieve the IP address of this Gist's author from GitHub::KV
  #
  # Returns a String
  def creator_ip
    @creator_ip ||= GitHub.kv.get(creator_ip_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  # Public: Was a gist fork updated after it was created?
  # Ignores modifications which immediately followed forking.
  #
  # Returns a Boolean
  def modified?
    updated_at - created_at > 1.minute
  end

  # Public: For API compatibility with Repository and Unsullied::Wiki
  #
  # Always returns false
  def supports_protected_branches?
    false
  end

  # Manage access to this gist. Disabling a gist
  # cuts of access to all protocols: git, ssh, web and api.
  #
  # Examples:
  #
  #   gist.access.disable("size", staff_user)
  #   gist.access.dmca_takedown(staff_user, "https://....")
  #
  # See GistGitRepositoryAccess for details.
  def access
    @access ||= GistGitRepositoryAccess.new(self)
  end

  def country_blocks
    access.country_blocks
  end

  # Public: Memoizing form of read_files
  #
  # oid - The commit OID to retrieve. If none is given use sha.
  #
  # Returns an Array of TreeEntry objects.
  def files(oid = nil)
    oid = ref_to_sha(oid) unless oid.nil?
    gist_sha = sha
    requested_oid = (oid || gist_sha)

    Failbot.push "gh.gist.commit.oid": requested_oid

    @read_files ||= {}
    @read_files[requested_oid] ||= read_files(requested_oid)
  end

  # Public: The default Gist Failbot context
  #
  # Returns a Hash for use with Failbot.push
  def failbot_context
    {
      "gh.spokes.spec": dgit_spec,
      "gh.gist.default_branch.oid": master_oid, # We've seen cases where this path returns data, and sha doesn't
      "git.commit.oid": sha,
      "gh.gist.id": id,
    }
  end

  # Public: Iterate over all files in this Gist
  #
  # Used in the view to get a consistent interface to the files regardless of
  # model state.
  #
  # If the gist has contents set, iterate over those.  This case
  # is for in process edits that were rejected due to validation errors.
  #
  # Otherwise, iterate the files collection which is populated via
  # GitRPC.
  #
  # Yields name, value, oid, and blob (if present) and returns the enumerator
  def files_for_view
    Enumerator.new do |yielder|
      if contents
        contents.each do |hash|
          # We can trigger an error if a user encounters a model validation error
          # when updating a gist with file(s) that have unicode characters.
          # Because we need to convert the filename to ASCII8BIT to avoid encoding errors in gitrpc,
          # we also need to force the encoding back to UTF-8 when rerendering the files in the view
          # following the update error.
          yielder.yield utf8(hash[:name]), hash[:value], hash[:oid], nil
        end
      elsif persisted?
        files.each do |file|
          yielder.yield file.display_name, file.data, file.oid, file
        end
      end
    end
  end

  # Public: An ordered version of `files`.
  #
  # Used by Spam check
  #
  # Files will be sorted alphabetically by filename except that READMEs will
  # be sorted first and autonamed files will be sorted last.
  #
  # Returns pairs of [tree_entry, "path/to/blob"]
  def files_with_path
    @files_with_path ||= sorted_files.map { |f| [f, f.name] }
  end

  # Public: Sorted file list
  #
  # oid - The commit OID to retrieve. If none is given use sha.
  #
  # Files will be sorted alphabetically by filename except that READMEs will
  # be sorted first and autonamed files will be sorted last.
  def sorted_files(oid = nil)
    files(oid).sort_by do |tree_entry|
      self.class.normalize_for_sort(tree_entry.name)
    end
  end

  def available?
    !(!active? || rpc.blank?)
  end

  def fork?
    !parent_id.nil?
  end

  def anonymous?
    user_id.nil?
  end

  def search_engine_indexable?
    return true unless anonymous?

    Gist::Anonymous::ALLOWLIST.include?(gist_id)
  end

  # Public: Determines if the gist was created by
  # an authenticated user or an anonymous one.
  #
  # Returns "owned" if this gist belongs to a user,
  # otherwise it returns "anonymous".
  def ownership
    anonymous? ? "anonymous" : "owned"
  end

  def user_param
    anonymous? ? ANONYMOUS_USERNAME : owner.to_param
  end

  def raw_url_for(file)
    "#{GitHub.gist_raw_url}/#{UrlHelper.escape_path(user_param)}/#{gist_id}/raw/#{file.id}/#{UrlHelper.escape_path(file.name)}"
  end

  # Who do we perform commits as?
  #
  # If Gist#committing_user is set (from the Web/API), prefer that.
  # Else, the current_user.
  # If no committing_user or the Gist has no user, Anonymous.
  def git_author
    committing_user || user || { name: "Anonymous", email: "anonymous@github.com" }
  end

  # Used for 'files/clone_options'.  Gist always allows ssh
  def ssh_enabled?
    true
  end

  def repository_spec
    "gist/#{repo_name}"
  end

  def namespace
    id.nil? ? "gist-creation" : "gist"
  end

  # Verify that the gist.git/hooks symlink is in place and symlinked
  # to the appropriate hooks directory. This is used exclusively in
  # development and test environments since the RAILS_ROOT is variable.
  def correct_hooks_symlink
    original = GitRPC.hooks_template
    begin
      GitRPC.hooks_template = "#{GitHub.gist3_repository_template}/hooks"
      rpc.symlink_hooks_directory
    ensure
      GitRPC.hooks_template = original
    end
  end

  # Check if the gist is "empty". Empty gists exist on disk but do
  # not have any branches, tags, or other refs and therefore no commits.
  #
  # NOTE Because this method is very frequently used in before filters and other
  # early-on code in controller actions, it has been highly optimized to avoid an
  # RPC call to the storage servers to determine emptyness. Do not change this
  # unless you know what you're doing / know how to measure these types of perf
  # changes.
  #
  # Returns true when the gist is empty, false otherwise.
  def empty?
    return @empty if defined?(@empty)
    @empty =
      begin
        if pushed_at.blank? && !fork?
          true
        elsif refs.empty?
          clear_ref_cache
          if refs.empty?
            true
          else
            # if refs.empty? does not return true again after clearing the ref
            # cache, then we have an incoherent cache. bump a graphite metric
            # to see whether this is actually something that happens in
            # production
            GitHub.dogstats.increment("gist.incoherent_refs_cache")
            false
          end
        end
      rescue Errno::ENOENT
        # If the repo doesn't exist on disk yet then yes, it's definitely
        # empty.
        true
      end
  end

  # Resets the git cache key so that it's up to date with the gists
  # pushed_at timestamp. This is typically only used in tests when a ref is
  # updated and you need to retrieve the updated ref values.
  def reset_git_cache
    remove_instance_variable :@empty if defined?(@empty)
    clear_ref_cache
  end

  # Rails's Object#present? delegates to blank?, which in turn delegates to
  # empty?. This method is overridden above, and can return true on an existing
  # repository, which makes Gist#present? return false.
  #
  # To avoid Gist#present? (and any other methods that delegate to blank?)
  # from unexpectedly returning false, we override blank? here.
  #
  # Returns a boolean.
  def blank?
    false
  end

  # Public: The collection object used to read Commit, Blob, Tree, and Tag
  # objects from the repository.
  #
  # Returns a RepositoryObjectsCollection bound to this repository.
  def objects
    @objects ||= RepositoryObjectsCollection.new(self)
  end

  # The Commit object at the head of main.
  def master_commit
    commits.find(master_oid) if master_oid
  end

  def gist_id
    repo_name.to_s
  end

  def raw
    raw_blob.try :data
  end

  def raw_blob
    files.detect { |blob| blob.text? }
  end

  def permalink
    if GitHub.flipper[:gist_permalink_update].enabled?(owner)
      "#{GitHub.gist_url}/#{name_with_owner}"
    else
      "#{GitHub.gist_url}/#{repo_url}"
    end
  end

  URI_TEMPLATE = Addressable::Template.new("#{GitHub.gist_url}/{repo_name}").freeze

  def path_uri
    return @path_uri if defined?(@path_uri)
    @path_uri = URI_TEMPLATE.expand(repo_name: to_param)
  end

  alias :async_path_uri :path_uri

  def repo_url(separator = "/")
    self
  end

  def full_repo_name
    "gist: " + repo_name
  end
  alias_method :name, :full_repo_name

  def path
    repo_name
  end

  def url_path(revision: nil)
    ["", repo_name, revision].compact.join("/")
  end

  def url(revision: nil)
    "#{GitHub.gist_url}#{url_path(revision: revision)}"
  end

  def clone_url
    "#{GitHub.gist_url}/#{repo_url}.git"
  end

  def push_url
    "#{GitHub.gist_url}/#{repo_url}.git"
  end

  def last_modified_at
    @last_modified_at ||= last_modified_with :user
  end

  # Public: Returns the internal URL to notify of a git push.
  #
  # dummy_arg - unused argument
  def post_receive_hook_url(dummy_arg = false)
    "#{GitHub.githooks_api_url}/internal/gists/#{name_with_owner}/git/pushes"
  end

  # if only git contents changed, update the timestamp in the corresponding db record
  def bump_updated_at
    self.updated_at = Time.now
  end

  # applies data from the `contents` hash
  def commit_contents_callback
    # contents can be missing on create if validation has been skipped
    return if self.contents.nil?

    begin
      commit_contents!(self.contents)
    rescue GitRPC::RequestTooLarge
      throw :abort
    end

    self.contents = nil
    unmemoize_all
    clear_ref_cache

    # unless this is the root commit, assume we're updating
    if parent
      self.save(validate: false) # save snippet after creating gist
    end
    async_backup(opts: { pushed_at: self.pushed_at })

    true
  end

  # Called as part of commit_contents_callback and Gist::Creator
  def unmemoize_all
    remove_instance_variable(:@files_with_path) if defined?(@files_with_path)
    remove_instance_variable(:@master_oid) if defined?(@master_oid)
  end

  include GitRepository::CommitsDependency
  include GitRepository::RefsDependency
  include Gist::RefsDependency

  def setup_git_repository
    creator =
      GitHub::RepoCreator.new(
        self,
        public: public?,
        template: GitHub.gist3_repository_template,
        default_branch: gist_repo_default_branch,
        nwo: "gist/#{repo_name}",
      )
    creator.init
  end

  # Public: read a blob oid from the repository.
  #
  # path       - The full path to the blob
  # commit_oid - [Optional] The string SHA1 object id of a commit
  #              for which to lookup the blob. Defaults to HEAD
  #
  # Returns a 40 character oid String object.
  # Raises GitRPC::ObjectMissing when the blob does not exist.
  def blob_oid_by_path(path, commit_oid = nil)
    rpc.gist_blob_oid_by_path(path, commit_oid || sha)
  end

  def default_file_oid(commit_oid = nil)
    commit_oid ||= sha
    return nil unless commit_oid
    rpc.gist_text_blob_oid(commit_oid)
  end

  ############################################################################
  ## Utility

  # Normalize a filename for sorting. Sorts README files first and autonamed
  # files last.
  #
  # name - The String filename
  #
  # Returns the normalized String.
  def self.normalize_for_sort(name)
    name = name.downcase
    if name =~ /^readme/i
      "__#{name}"
    elsif autonamed?(name)
      "|#{name}"
    elsif name.index("/")
      name.gsub(%r{[^/]+/}, '_\0')
    else
      name
    end
  end

  # Test whether a filename is autonamed.
  #
  # filename - The String filename without path.
  #
  # Returns the Boolean answer.
  def self.autonamed?(filename)
    filename =~ /^gistfile\d+$/
  end

  # Is the given document indexable? Certain content is excluded from
  # indexing because they do not contain data that is worth searching for.
  #
  # body - The String body of the document.
  #
  # Returns the Boolean answer.
  def indexable_doc?(body)
    s = body[0..MAX_BINARY_TEST_SIZE].split(//)
    ((s.size - s.grep(" ".."~").size) / s.size.to_f) <= 0.30
  end

  def git_lfs_enabled?
    false
  end

  # Public: The title for this gist.
  #
  # We truncate at MAX_GIST_TITLE_LENGTH limit if the title is longer.
  def title
    raw_title.to_s.first(MAX_GIST_TITLE_LENGTH)
  end

  attribute :description, StringFromBinary.new

  # Internal: The "title" for this gist.
  # If the user named a file, we use that as the title.
  # Otherwise gist:repo_name.
  #
  # Returns a String.
  def raw_title
    name = rpc.gist_title(sha)
    name ? name : default_title
  rescue GitRPC::Error, GitHub::DGit::UnroutedError => boom
    Failbot.report_user_error(boom, failbot_context) if boom.is_a? GitRPC::Error
    default_title
  end

  # Public: The gist's visibility.
  #
  # Returns 'public' or 'secret'.
  def visibility
    public? ? "public" : "secret"
  end

  # Since the AR public? is method missing, add this for Entity#public? compat
  def public?
    !!self.public
  end

  def secret?
    !public?
  end
  # For Entity#private? compatibility
  alias private? secret?

  # For Entity compat
  def entity
    self
  end

  def name_with_owner(separator = "/")
    "#{user_param}#{separator}#{self}"
  end
  alias full_name name_with_owner
  alias nwo name_with_owner

  def name_with_owner_for_archive
    "gist/#{self}"
  end

  # not multi-tenant aware because gists aren't supported in Proxima
  alias token_scope name_with_owner_for_archive

  def readonly_name_with_owner(separator = "/")
    ActiveRecord::Base.connected_to(role: :reading) { name_with_owner(separator) }
  end

  def name_with_display_owner
    "#{owner_display_login}/#{self}"
  end

  def owner_display_login
    User.to_display_login(user_param)
  end

  # Override clone_host_name from GitRepository::UrlMethods
  #
  # Returns a String uri.
  def clone_host_name
    if GitHub.gist3_domain?
      GitHub.gist3_host_name
    else
      super
    end
  end

  # Used by GitRepository::UrlMethods
  #
  # If we have a gist3 domain configured and we're not in
  # development just use `repo_name`.
  #
  # In all other cases use `gist/repo_name`.
  def short_git_path
    if GitHub.gist3_domain? && !Rails.env.development?
      repo_name
    else
      "gist/#{repo_name}"
    end
  end

  # Public: The repo name with the title
  #
  # This will usually be in the form of
  # :username/:first-file-name.ext
  #
  # This is used to display human readable fork names in the UI.
  # nwo was considered, but substantial change/rework of parts of the
  # API usage would be required.
  def name_with_title
    "#{user_param}/#{title}"
  end

  def pullable_by?(user)
    async_pullable_by?(user).sync
  end
  alias_method :readable_by?, :pullable_by?

  # Entity compat: Everyone can read any Gist because the world is built on trust
  def async_pullable_by?(user)
    Promise.resolve(true)
  end
  alias_method :async_readable_by?, :async_pullable_by?

  # Who can admin this Gist?
  # Practically speaking this means who can edit the Gist, manipulate it's
  # comments, or edit it's description.
  def async_adminable_by?(actor)
    return Promise.resolve(false) unless actor
    return Promise.resolve(true) if actor.site_admin?

    async_user.then { |user| user == actor }
  end

  # This method is use exclusively in show_page view_components
  # to determine if the current_user is the owner of the gist.
  # Currently this method is leveraged in Gists::ShowPageView and Gists::BlobView.
  #
  # We distinguish between this method and async_adminable_by?
  # because we want staff users to continue to be able to edit or
  # delete individual gist comments, but we don't want them to have the
  # ability to delete or edit the gist itself within the general GitHub UI
  #
  # Staff users may still delete gists via stafftools
  def async_ui_content_adminable_by?(actor)
    return Promise.resolve(false) unless actor
    async_user.then { |user| user == actor }
  end

  def ui_content_adminable_by?(actor)
    async_ui_content_adminable_by?(actor).sync
  end

  def adminable_by?(actor)
    async_adminable_by?(actor).sync
  end
  alias writable_by? adminable_by?
  alias pushable_by? adminable_by?

  # Is this anonymous Gist deleteable by this IP address?
  #
  # Returns a Boolean
  def deletable_by_ip?(requester_ip)
    return false if GitHub.enterprise?
    return false unless anonymous?
    return false unless creator_ip

    SecurityUtils.secure_compare(creator_ip, requester_ip)
  end

  # Was this Gist recently created?
  def recently_created?
    (pushed_at.to_f / 60).round == (created_at.to_f / 60).round
  end

  # Commit the contents to the backing git repository for this Gist
  #
  # files    - An array of file hashes of the form
  #            {
  #              :name   => 'filename',
  #
  #              # value can be nil in the case of binary edits from the web.
  #              :value  => 'file contents',
  #
  #              :oid    => 'oid of existing file if present'
  #              # Should we mark this file (aka oid) as deleted?
  #
  #              :delete => true|false
  #            }
  # author - The user authoring this commit?
  #
  # Returns nothing.
  def commit_contents!(files, author = git_author)
    metadata  = { message: "", author: author }
    parent    = master_commit

    # Grab the current tree so we can commit unchanged binary files.
    gist_files = sha ? files(sha) : []
    generated_filename_index = gist_files.count { |f| f.name.to_s =~ /gistfile/ }

    begin
      commit = commits.create(metadata, parent && parent.oid) do |stage|
        files.each do |file|
          filename, data, oid, delete = file[:name].to_s.strip, file[:value], file[:oid], !!file[:delete]

          if filename.blank?
            filename = "gistfile#{generated_filename_index += 1}.txt"
          end

          # Find original file via filename
          original_file = gist_files.detect { |f| f.name.b == filename.b }
          # Find original file via oid if provided and filename search failed
          original_file ||= gist_files.detect { |f| f.oid == oid } if oid

          # We always want to attempt to remove line endings from new files.
          # The original data will be returned if the preserve_line_endings flag is enabled,
          # or if an existing file was already saved with Windows-style newlines.
          #
          # If the content has even a single Windows line-ending, we normalize the entire file to that.
          # More explanation in https://github.com/github/github/pull/95026
          if original_file && !delete
            # Gists only load as much content from a file that fits within 1MB. However, we still
            # display those files on the edit view. Because we can't be sure that the entire
            # file has actually been loaded into memory, we can't rely on the original_file data
            # attribute. So, we move on to the next file. Note that this means the user cannot edit the title
            # of these files either. This is not ideal, but we want to prevent data loss now, and update
            # the UI later.
            next if data.nil?

            if original_file.binary?
              # Web edits on binary files never send back the data
              # so we re-populate it here. We also dont want to remove any characters from the file.
              data ||= original_file.data
            else
              data = remove_windows_line_endings(data) unless original_file.has_windows_line_endings?
            end
          else
            data = remove_windows_line_endings(data)
          end

          if original_file && delete
            # Remove cases exist in index and data.blank?
            stage.remove filename.b
          elsif original_file && original_file.name.b != filename.b
            # Moves exist in index and have differing names
            stage.move original_file.name.b, filename.b, data
          else
            stage.add filename.b, data
          end
        end
      end
    rescue GitRPC::RequestTooLarge => e
      errors.add(:contents, "are too large and cannot be saved")
      raise e
    end

    ref = heads.find_or_build(self.default_branch)
    ref.update(commit, author, post_receive: autorun_post_receive?)

    if new_record?
      self.pushed_at = Time.now
    else
      update_column :pushed_at, Time.now
    end

    commit.oid
  end

  # Internal: Should we auto run the post receive hook?
  #
  # This is true whenever the Gist is already persisted.
  def autorun_post_receive?
    persisted?
  end

  # Internal. For fork that need to refresh the parent as needed
  def touch_parent
    parent.touch if parent
  end

  def timeline_updated_at_for(viewer)
    updated_at
  end

  # Public: Grab all timeline items sorted by creation time
  #
  # Takes an options hash to limit the returned items -- otherwise all
  # items are returned.
  #
  # viewer - the User that is viewing the conversation (current_user)
  #
  # Options
  #  :since => Grab all items only after the specified Time
  #  :permalink_comment_id => id of comment being permalinked to, will grab that comment and all later ones
  #  :before_comment_id  => used in pagination - The id of the oldest loaded comment on the previous page.
  #                         If this is passed, the previous "page" of comments is retrieved
  #                         (up to COMMENTS_PER_PAGE comments with IDs lower than before_comment_id).
  #  :after_comment_id   => used in pagination - The id of the latest comment loaded on the previous page.
  #                         Note that the latest comment is not rendered but grabbed from the DB to determine whether
  #                         to show a "next" link.
  #
  # Returns collection of GistComments
  def timeline_for(viewer, options = {})
    permalink_comment_id = options[:permalink_comment_id]
    before_comment_id = options[:before_comment_id]
    after_comment_id = options[:after_comment_id]
    forward_in_time_pagination = (permalink_comment_id || after_comment_id) && options[:forward_in_time_pagination]

    filtered_comments = self.comments
                            .filter_spam_for(viewer)
                            .order(id: forward_in_time_pagination ? :asc : :desc)

    if options[:since]
      filtered_comments = filtered_comments.where("created_at > ?", options[:since] || 0)
    end

    if forward_in_time_pagination
      filtered_comments = filtered_comments.where("id >= ?", [permalink_comment_id.to_i, after_comment_id.to_i].max).limit(COMMENTS_PER_PAGE + 1)
    elsif permalink_comment_id
      filtered_comments = filtered_comments.where("id >= ?", permalink_comment_id.to_i)
    else
      filtered_comments = filtered_comments.where("id < ?", before_comment_id&.to_i || 2**31).limit(COMMENTS_PER_PAGE)
    end

    filtered_comments.sort_by(&:id)
  end

  def archive_command(commitish, type, actor_id: nil, actor_token: nil)
    GitRepository::ArchiveCommand.new(self, commitish, type, actor_id: actor_id)
  end

  # Bump the version here to roll gist cache in the views, and etags.
  def cache_key
    "v1.0:#{id}/#{user_param}/#{updated_at.iso8601}/#{sha}"
  end

  # Used for etags with Gists
  # Varies based on the viewing user
  def viewer_cache_key(viewer)
    viewer_cache_key = viewer ? viewer.login : "public"
    "#{cache_key}:#{viewer_cache_key}"
  end

  def spokes_cache_key
    "gist:#{repo_name}"
  end

  # Retrieve the blob oid for a given path, and possibly revision.
  #
  # This method is used to support **app/api/internal/raw.rb**
  #
  # path                - The file name/path
  # commit_or_blob_oid  - A commit, or blob oid.  The legacy raw api accepted blob oids,
  #                       so we have to distinguish between the two here, and do a
  #                       little sleuthing.
  #
  # Returns the blob_oid, or raises.
  # Exceptions are caught by the `gitrpc` wrapping block in app/api/internal/raw.rb
  def retrieve_blob_oid_for_path(path, commit_or_blob_oid = nil)
    possible_blob = rpc.read_objects([commit_or_blob_oid]).first if commit_or_blob_oid

    if possible_blob && possible_blob["type"] == "blob"
      # commit_or_blob_oid was actually a blob oid
      return possible_blob["oid"]
    end

    if path.blank?
      default_file_oid
    else
      blob_oid_by_path(Addressable::URI.unencode(path), commit_or_blob_oid)
    end
  end

  # This updates the push counts w/o invoking callbacks.
  # Used by the git hook infrastructure.
  def increment_push_counts
    # Ensure we always have values here, at least in dev sometimes
    # MySQL comes back with nil even though there is a default set.
    self.pushed_count ||= 0
    self.pushed_count += 1

    self.pushed_count_since_maintenance ||= 0
    self.pushed_count_since_maintenance += 1

    self.class.where(id: id).update_all(
      pushed_count: pushed_count,
      pushed_count_since_maintenance: pushed_count_since_maintenance,
    )
  end

  # This updates the push info w/o invoking callbacks.
  # Used by the git hook infrastructure.
  #
  # NOTE: We also update the updated_at here as Gist UI caches are tied to
  #       that.
  def update_pushed_at(time = Time.now)
    self.pushed_at = time
    self.updated_at = time

    self.class.where(id: id).update_all(pushed_at: time, updated_at: time) unless id.nil?
  end

  # For Instrumentation
  def event_payload_visibility
    public? ? "public" : "secret"
  end

  def event_prefix
    :gist
  end

  def event_payload
    payload = {
      :actor => user,
      :user => user,
      :visibility => event_payload_visibility,
      :fork => fork?,
      event_prefix => self,
    }

    if parent_id && parent
      payload[:fork_parent] = parent
    end

    payload
  end

  # Used by the audit log to convert a Gist model into the payload
  # we return here.
  def event_context(prefix: :gist)
    {
      "#{prefix}_id".to_sym => id,
      prefix => name_with_owner,
    }
  end

  # Helper method for transferring a Gist to another user. Only for console
  # use until we have time to build out Stafftools interface for transferring.
  def transfer_to(new_owner)
    self.tap do |gist|
      gist.user = new_owner
      gist.save!
    end
  end

  # Public: Synchronize this gist with its representation in the search
  # index. If the gist is newly created or modified in some fashion,
  # then it will be updated in the search index. If the gist has been
  # destroyed, then it will be removed from the search index. This method
  # handles both cases.
  def synchronize_search_index
    GistSynchronizeSearchIndexJob.perform_later(id)
  end

  # Public: Should we be adding this gist to the search index? Reasons for
  # keeping it out of the search index are:
  #   - Not routed on the file servers
  #   - The user is a spammer
  #   - Disabled by an admin
  #
  # Return `true` if we should add the repository to the search index; return
  # `false` if we should not.
  #
  def gist_is_searchable?
    # Gist is unavailable if the host is unknown
    # OR the gist is deleted?
    return false if !available?
    # When RPC can't connect to the host.
    return false if offline?
    # When the gist owner is spammy
    return false if spammy?
    # When the gist is anonymous
    return false if anonymous?
    # When the gist has been disabled for any reason
    return false if access.disabled?
    # When the gist has too many files
    return false if files.length > 100
    # The gist is safe to index
    true

  rescue StandardError => boom # rubocop:todo Lint/GenericRescue
    Failbot.report(boom, failbot_context)
    false
  end

  # No-op. Custom hooks aren't supported for gist.
  def check_custom_hooks(old_oid, new_oid, qualified_name, options = {})
  end

  # Public: prevents timestamps from being updated during
  # the execution of a block. When the block is finished,
  # record_timestamps is returned to its previous value.
  #
  # Useful for preventing `updated_at` from being touched
  # which has a lot of UI consequences.
  def self.without_timestamps
    previous_record_timestamps = Gist.record_timestamps
    Gist.record_timestamps = false

    yield
  ensure
    Gist.record_timestamps = previous_record_timestamps
  end

  # Noop, so we match the Repository API.
  #
  # TODO: Sign Gist commits?
  #
  # Returns nil.
  def sign_commit(*args)
    nil
  end

  # Used for instrumentation to capture changes before a gist is updated.
  def gist_snapshot
    # We slice the attributes here with the known column names
    # because during a migration, attributes might have been loaded
    # with `SELECT *` and already see a new attribute the Gist model
    # doesn't really know about yet. By slicing it with the known column
    # names we ensure there's no unknown columns being set.
    gist = Gist.new(self.attributes.slice(*Gist.column_names))

    {
      files: Gist.limit_files(gist.files),
      gist: gist,
      head_sha: gist.sha,
    }
  end

  def instrument_hydro_update_event(actor:, previous_gist_snapshot:)
    GlobalInstrumenter.instrument "gist.update", {
      actor: actor,
      gist: self,
      files: Gist.limit_files(self.files),
      previous_gist_snapshot: previous_gist_snapshot,
      feature_flags: feature_flags_on_gists,
    }
  end

  def lfs_in_archives_enabled?
    false
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access if anonymous? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end

  def async_target_for_conditional_access
    async_user.then do |user|
      next :no_target_for_conditional_access if user.nil?
      user
    end
  end

  # Determines the target for for conditional access for multiple Gists instances
  #
  # gists - an enumerable of Gists
  #
  # returns Hash[Gist] => (target for conditional access || :no_target_for_conditional_access)
  def self.multiple_target_for_conditional_access(gists)
    ConditionalAccess::Filter.ensure_with_class(gists, Gist)

    owners = User.where(id: gists.pluck(:user_id))
    id_to_owner = owners.each_with_object({}) { |v, h| h[v.id] = v }
    result = {}
    gists.each do |gist|
      result[gist] = id_to_owner[gist.user_id] || :no_target_for_conditional_access
    end

    result
  end

  def feature_flags_on_gists
    SecretScanning::Instrumentation::GistServiceFlags.new(self).gist_scanning_service_flags
  end

  # Gists are only associated with users, so we stub out this method for
  # API compatibility with Repository
  def organization
    nil
  end

  def gist_repo_default_branch
    user&.default_new_repo_branch || "main"
  end

  def aggregate_file_size
    files.reduce(0) { |total, file| total += file["size"] }
  end

  # Gists with a total on-disk size of greater than ~1MB start to truncate files
  # This can cause data-loss issues when users try and edit files in these gists,
  # as their content won't appear correctly.
  def has_truncated_files?
    aggregate_file_size > GitRPC::Backend.tree_summary_maximum_data_size
  end

  private

  def subscribe_author
    subscribe(user, :author)
  end

  def destroy_notification_dependents
    list = if anonymous?
      User.ghost
    else
      # If we don't have the user anymore, fake it.
      user || User.new.tap { |u| u.id = user_id }
    end
    GitHub.newsies.async_delete_all_for_thread(list, self)
  end

  def old_visibility
    public_before_last_save ? "public" : "secret"
  end

  def audit_visibility_change
    instrument :visibility_change, old_visibility: old_visibility
  end

  # Internal: Before create callback used to set default attributes values for a
  # record that's about to be created.
  def set_default_values
    self.pushed_at ||= Time.now
    self.pushed_count ||= 0
    self.pushed_count_since_maintenance ||= 0
    self.maintenance_status  ||= "complete"
    self.last_maintenance_at ||= Time.now
    self.last_maintenance_attempted_at ||= Time.now
  end

  # Files for this Gist, preloading any file contents.
  #
  # oid - The commit OID to retrieve. If none is given use sha.
  #
  # Returns an Array of TreeEntry objects.
  def read_files(requested_oid = nil)
    # Likely if gist_sha is nil, refs/heads/main couldn't be found
    if requested_oid.nil?
      return []
    end

    blobs(requested_oid)
  rescue GitRPC::BadRepositoryState, GitRPC::InvalidRepository, GitRPC::ObjectMissing => boom
    Failbot.push failbot_context
    Failbot.report boom, app: "github-user"
    []
  end

  # Instrument Gist Creation
  # Stats are handled in config/instrumentation/gist.rb
  def instrument_creation
    instrument :create

    GlobalInstrumenter.instrument "gist.create", {
      actor: user,
      gist: self,
      files: Gist.limit_files(self.files),
      feature_flags: feature_flags_on_gists
    }
  end

  # Internal: The fallback title for when rpc.gist_title can't be retrieved.
  # In order to avoid leaking secret Gist IDs to Google Analytics,
  # this gets sanitized via a regex in JS at app/assets/modules/github/google-analytics-overrides.js
  # Be sure to update the regex if you change the format of the title
  def default_title
    "gist:#{repo_name}"
  end

  def empty_file?(file_content)
    file_content.nil? || file_content.blank?
  end

  # Internal: Replaces any instances of \r\n with \n.
  # Need to do this because forms POST with \r\n.
  #
  # content - Contents of a file from the `commit_files!` Array of {value:'',name:''} Hashes.
  #
  # Returns string.
  def remove_windows_line_endings(content)
    if empty_file?(content) || preserve_line_endings
      return content
    end

    content.gsub("\r\n", "\n")
  end

  # Validation: Ensure that the user has verified at least one email
  #
  # This validation fails when:
  # - The user creating this gist has no verified emails
  def ensure_user_has_verified_email
    return if GitHub.anonymous_gist_creation_enabled? && user.nil?
    if user.must_verify_email?
      errors.add(:user, "must have a verified email")
    end
  end

  # Validation: Ensure the user is not trade restricted before creating a secret gist
  #
  # This validation fails when:
  # - The user creating this secret gist has been flagged for trade restriction
  def ensure_user_not_trade_restricted_for_secret
    if !public && user&.has_any_trade_restrictions?
      errors.add(:base, TradeControls::Notices.notice_as_plaintext(:billing_account_restricted))
    end
  end

  # Validation: Ensure all files have the proper structure.
  #
  # This validation fails when:
  # - files is not an Array
  # - any of the contents of files are not Hashes
  def ensure_valid_file_information
    return if contents.nil?

    if !contents.is_a?(Array) || contents.any? { |file| !file.is_a?(Hash) }
      errors.add(:contents, "are invalid")
    end
  end

  # Validation: Ensure all files have a unique name
  #
  # This validation fails when:
  # - any filename is repeated
  def ensure_unique_filenames
    return if contents.nil? || !contents.is_a?(Array)

    filenames = contents.select { |f| f[:value].present? }.map do |f|
      f[:name]
    end

    if filenames.any? { |filename| filename.present? && filenames.count(filename) > 1 }
      errors.add(:contents, "must have unique filenames")
    end
  end

  # Validation: Ensure no subdirectories are added to this Gist.
  #
  # This validation fails when:
  # - any filename includes "/"
  def ensure_no_subdirectories
    return if contents.nil?

    if contents.any? { |file| file.is_a?(Hash) && file[:name].to_s.include?("/") }
      errors.add(:contents, "files can't be in subdirectories or include '/' in the name")
    end
  end

  # Validation: Ensure no invalid file paths are present.
  #
  # This validation fails when any file path fails the
  # GitHub::GitFile.validate_path check
  def ensure_valid_paths
    return if contents.nil?

    if contents.any? { |file| file.is_a?(Hash) && !file[:name].to_s.blank? && GitHub::GitFile.validate_path(file[:name].to_s) }
      errors.add("Whoops,", "files can't contain malformed path components.")
    end
  end

  # Validation: Ensure new Gists w/o files can't be created.
  #
  # Permit edits w/o files being re-submitted, and forking.
  #
  # This validation fails when:
  # - an unsaved, non-fork gist has nil or empty files.
  def ensure_files_present
    return if persisted? || fork?
    errors.add(:contents, "can't be empty") if contents.blank?
  end

  # Validation: Ensure all files have file content
  #
  # This validation fails when:
  # - any file has blank/empty content
  def ensure_files_have_content
    return if contents.nil?

    if contents.any? { |file| file.is_a?(Hash) && file[:oid].blank? && file[:value].blank? }
      errors.add(:contents, "can't be empty")
    end
  end

  # Validation: Ensure Gist file contents are strings.
  #
  # This validation fails when:
  # - Any Gist file contents are a non-String (hash, int, etc)
  def ensure_file_contents_are_strings
    return if contents.nil?

    if contents.any? { |file| file[:value] && !file[:value].instance_of?(String) }
      errors.add(:contents, "must have non-empty string data")
    end
  end

  # Launch a scan looking for sensitive tokens leaked in this Gist.
  #
  # Returns nothing.
  def scan_for_tokens
    return unless SecretScanning::Features::Gist::PublicScanning.new(self).enabled?
    # When visibility changes from private to public you will get a key like
    # "public"=>[false, true]
    return unless previous_changes.has_key?("public")
    # Check to make sure the "before" state was not "true" (i.e. already
    # public).
    return if previous_changes["public"].first

    # Instrument event in hydro for the moda service to process
    GlobalInstrumenter.instrument("secret_scanning.backfill.gist", {
      gist: self,
      actor: user,
      owner: user,
      feature_flags: feature_flags_on_gists,
      type: :START,
      requested_at: self.updated_at,
    })
  end

  # Private: Strips out invalid UTF-8 characters from the description.
  # This allows us to lazily fix invalid gists created before we started
  # validating unicode.
  #
  # Called as a before_validation hook.
  def scrub_description
    return true if description.nil? || description.valid_encoding?

    self.description = description.scrub
  end

  # Public gists cannot be made private due to privacy assumptions. i.e. if
  # someone wants to erase a gist from public access, they must delete it.
  def prevent_public_gists_from_becoming_private
    if changed_attributes["public"] == true
      errors.add(:base, "To remove public content, delete the gist instead.")

      throw :abort
    end
  end

  # Store an anonymous Gist's author's IP in GitHub::KV
  # We allow an anonymous user to delete their Gists within 30 minutes of creation
  #
  # Returns nothing.
  def store_creator_ip
    return if GitHub.enterprise?
    return unless anonymous?

    GitHub.kv.set(creator_ip_key, creator_ip, expires: 30.minutes.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
  rescue GitHub::KV::UnavailableError
    # move along without saving creator's IP
  end
end
