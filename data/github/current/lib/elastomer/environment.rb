# typed: true
# frozen_string_literal: true

module Elastomer

  # The Environment contains information about the indices and adapters
  # available to the Elastomer framework. This information is determined
  # solely by the source code; there are no settings in here that can be
  # updated or modified at runtime.
  #
  # See Elastomer::Config for runtime modifiable settings.
  module Environment
    extend self
    include Kernel

    # A String that is appened to all index names. This is great when you want
    # to spin up indices in a test environment - setting postfix to 'test'
    # will give you index names like 'foo-test' instead of the regular 'foo'.
    attr_reader :postfix

    def postfix=(str)
      @postfix = str
      @postfix = "-#{str}" if str && str !~ /\A-/
    end

    # Given a class or an index name returns a canonical index name including
    # the Rails environment and/or test environment number.
    #
    # obj - A Class or a String
    #
    # Returns an index name as a String.
    def index_name(obj)
      slicer = Slicer.new

      if obj.is_a? Class
        slicer.index = obj
      else
        begin
          slicer.fullname = obj.to_s
        rescue ArgumentError
          slicer.index = obj.to_s
        end
      end

      slicer.index
    end

    # A logical index name is constructed from the index Class. They are used
    # to figure out which concrete indices should be written to and read from
    # by the Elastomer framework.
    #
    # Noramlly a concrete index has a trailing number. We use these in order
    # to upgrade to a new index. The logical index name is used to assign a
    # read alias to a cocrete index.
    #
    #     'issues' --> 'issues-3'
    #
    # 'issues' is the logical index name, and it is used as an alias pointing
    # to 'issues-3' which is the concrete index that is currently being used.
    #
    # obj - The index Class
    #
    # Returns the logical index name as a String.
    def logical_index_name(clazz)
      clazz.logical_index_name
    end

    # Returns the Array of index names available in source code.
    def index_names
      indices.map(&:logical_index_name)
    end

    # Returns the Array of Elastomer::Index classes available in source code.
    def indices
      return @indices if defined? @indices

      indices = ::Elastomer::Indexes
      @indices = indices.constants.map { |sym| indices.const_get(sym, false) }
      @indices.reject! { |clazz| !(clazz < ::Elastomer::Index) }
      @indices
    end

    # Lookup the index class either by name or by adapter type. If a String is
    # given, we assume it is an index name, and we try to find a class of the
    # same name in the indices location. If an adapter instance is given, we
    # lookup the index from the adapter `index_name` method.
    #
    # obj - Either an index type as a String or an Adapter instance.
    #
    # Returns an index Class.
    sig { params(obj: T.any(String, Adapter, Object)).returns(T.class_of(Index)) }
    def lookup_index(obj)
      classname =
        case obj
        when Adapter
          if obj.class.index_name
            obj.class.index_name
          else
            raise UnknownIndex, "The adapter `#{obj.class.name}' is not mapped to any index"
          end
        when String
          classify_index_name(obj)
        else
          raise ::Elastomer::UnknownIndex, "Could not map #{obj.inspect} to an index"
        end

      # O_O - 2015-05-07
      #
      # This check exists because of "magical" interactions between Rails and
      # Ruby. On the first invocation, the `const_get` method will walk up the
      # namespaces looking for `classname` regardless of the `false` inherit
      # flag we are passing in. On subsequent invocations, the method will do
      # the right thing and raise a NameError. So we have to explicitly check
      # for the index class in the `constants` before attempting to load it.
      if ::Elastomer::Indexes.constants.include? classname.to_sym
        ::Elastomer::Indexes.const_get(classname, false)
      else
        raise ::Elastomer::UnknownIndex, "Elastomer::Indexes::#{classname} does not exist"
      end

    rescue NameError
      raise ::Elastomer::UnknownIndex, "Elastomer::Indexes::#{classname} does not exist"
    end

    # Lookup the repair job class for a given index. You can pass in the index
    # class or the index name. If a String is given we assume it is an index
    # name. If a Class is given we assume it is an index class.
    #
    # obj - Either an Elastomer::Index class or an index name String.
    #
    # Returns a repair job Class.
    def lookup_repair_job(obj)
      name =
        if obj.is_a?(Class) && obj < ::Elastomer::Index
          obj.name&.demodulize
        elsif obj.is_a?(String)
          classify_index_name(obj)
        else
          raise ::Elastomer::Error, "Could not map #{obj.inspect} to an index repair job"
        end

      case name
      when "AzureModels";            RepairAzureModelsIndexJob
      when "CodeSearch";             RepairCodeSearchIndexJob
      when "Commits";                RepairCommitsIndexJob
      when "DependabotAlerts";       RepairDependabotAlertsIndexJob
      when "Discussions";            RepairDiscussionsIndexJob
      when "Enterprises";            RepairEnterprisesIndexJob
      when "Gists";                  RepairGistsIndexJob
      when "Issues";                 RepairIssuesIndexJob
      when "Labels";                 RepairLabelsIndexJob
      when "MarketplaceListings";    RepairMarketplaceListingsIndexJob
      when "MemexProjectItems";      RepairMemexProjectItemsIndexJob
      when "RepositoryActions";      RepairRepositoryActionsIndexJob
      when "PullRequests";           RepairPullRequestsIndexJob
      when "Showcases";              RepairShowcasesIndexJob
      when "Repos";                  RepairReposIndexJob
      when "Releases";               RepairReleasesIndexJob
      when "TeamDiscussions";        RepairTeamDiscussionsIndexJob
      when "Wikis";                  RepairWikisIndexJob
      when "Users";                  RepairUsersIndexJob
      when "Topics";                 RepairTopicsIndexJob
      when "ProjectCards";           RepairProjectCardsIndexJob
      when "Projects";               RepairProjectsIndexJob
      when "RegistryPackages";       RepairRegistryPackagesIndexJob
      when "Vulnerabilities";        RepairVulnerabilitiesIndexJob
      when "WorkflowRuns";           RepairWorkflowRunsIndexJob
      else
        raise ::Elastomer::Error, "Could not map #{obj.inspect} to an index repair job"
      end
    end

    # Given an adapter name return the adapter Class.
    #
    # type - The adapter name as a String
    #
    # Returns the Class for the requested adapter.
    # Raises Elastomer::UnknownAdapter if the adapter type does not exist.
    def lookup_adapter(type)
      classname = type.to_s.tr("-", "_").camelize.split("::").last
      ::Elastomer::Adapters.const_get(classname, false)
    rescue NameError
      raise ::Elastomer::UnknownAdapter, "Elastomer::Adapters::#{classname} does not exist"
    end

    # Lookup the index class slicer either by name or by adapter type. If a
    # String is given, we assume it is an index name, and we try to find a class
    # of the same name in the indices location. If an adapter instance is given,
    # we lookup the index from the adapter `index_name` method.
    #
    # obj - Either an index type as a String or an Adapter instance.
    #
    # Returns a Slicer instance.
    def lookup_slicer(obj)
      return obj.slicer if obj.respond_to?(:slicer)
      lookup_index(obj).slicer
    end

    # Internal: Given an index name string, return the index class name as a
    # String. This returned name will not contain any module information -
    # just the class name.
    #
    # name - the index name String
    #
    # Returns index class name as a String.
    def classify_index_name(name)
      slicer = Slicer.new(fullname: name)
      slicer.index_class_name
    rescue ArgumentError
      name.tr("-", "_").camelize.split("::").last
    end
  end
end
