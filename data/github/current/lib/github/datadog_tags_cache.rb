# typed: true
# frozen_string_literal: true

require "github/tagging_helper"

module GitHub
  class DatadogTagsCache
    attr_reader :pod_name, :controller_action, :method_controller_action_service, :controller_action_service_method_status_category

    SQL_OPERATION_SELECT  = "rpc_operation:select"
    SQL_OPERATION_DELETE  = "rpc_operation:delete"
    SQL_OPERATION_INSERT  = "rpc_operation:insert"
    SQL_OPERATION_UPDATE  = "rpc_operation:update"
    SQL_OPERATION_REPLACE = "rpc_operation:replace"
    SQL_OPERATION_UNKNOWN = "rpc_operation:unknown"

    SQL_OPERATIONS = Hash.new(SQL_OPERATION_UNKNOWN)
    SQL_OPERATIONS[:select]  = SQL_OPERATION_SELECT
    SQL_OPERATIONS[:delete]  = SQL_OPERATION_DELETE
    SQL_OPERATIONS[:insert]  = SQL_OPERATION_INSERT
    SQL_OPERATIONS[:update]  = SQL_OPERATION_UPDATE
    SQL_OPERATIONS[:replace] = SQL_OPERATION_REPLACE

    SQL_CONNECTION_ROLE_READING      = "connection_role:reading"
    SQL_CONNECTION_ROLE_READING_SLOW = "connection_role:reading_slow"
    SQL_CONNECTION_ROLE_WRITING      = "connection_role:writing"
    SQL_CONNECTION_ROLE_UNKNOWN      = "connection_role:unknown"

    SQL_CONNECTION_ROLES = Hash.new(SQL_CONNECTION_ROLE_UNKNOWN)
    SQL_CONNECTION_ROLES[:reading]      = SQL_CONNECTION_ROLE_READING
    SQL_CONNECTION_ROLES[:reading_slow] = SQL_CONNECTION_ROLE_READING_SLOW
    SQL_CONNECTION_ROLES[:writing]      = SQL_CONNECTION_ROLE_WRITING

    SQL_CLUSTER_AUTHND_PRODUCTION = "cluster:authnd-production"
    SQL_CLUSTER_BALLAST = "cluster:ballast"
    SQL_CLUSTER_BILLING = "cluster:billing"
    SQL_CLUSTER_COLLAB = "cluster:collab"
    SQL_CLUSTER_COMMITS = "cluster:commits"
    SQL_CLUSTER_CONFIGURATIONS = "cluster:configurations"
    SQL_CLUSTER_COPILOT = "cluster:copilot"
    SQL_CLUSTER_IAM = "cluster:iam"
    SQL_CLUSTER_IAM_ABILITIES = "cluster:iam_abilities"
    SQL_CLUSTER_ISSUES_PULL_REQUESTS = "cluster:issues-pull-requests"
    SQL_CLUSTER_LODGE = "cluster:lodge"
    SQL_CLUSTER_MEMEX = "cluster:memex"
    SQL_CLUSTER_MYSQL1 = "cluster:mysql1"
    SQL_CLUSTER_MYSQL2 = "cluster:mysql2"
    SQL_CLUSTER_MYSQL5 = "cluster:mysql5"
    SQL_CLUSTER_NOTIFICATIONS_DELIVERIES = "cluster:notifications_deliveries"
    SQL_CLUSTER_NOTIFICATIONS_ENTRIES = "cluster:notifications_entries"
    SQL_CLUSTER_NOTIFICATIONS_SUMMARIES = "cluster:notifications_summaries"
    SQL_CLUSTER_NOTIFY = "cluster:notify"
    SQL_CLUSTER_OCTOSHIFT = "cluster:octoshift"
    SQL_CLUSTER_PERMISSIONS = "cluster:permissions"
    SQL_CLUSTER_REPOSITORIES = "cluster:repositories"
    SQL_CLUSTER_REPOSITORIES_ACTIONS_CHECKS = "cluster:repositories-actions-checks"
    SQL_CLUSTER_REPOSITORIES_PUSHES_SHARDED = "cluster:repositories-pushes-sharded"
    SQL_CLUSTER_SECURITY_OVERVIEW = "cluster:security-overview"
    SQL_CLUSTER_UNKNOWN = "cluster:unknown"

    SQL_CLUSTER_NAMES = {
      "authnd-production": SQL_CLUSTER_AUTHND_PRODUCTION,
      "ballast": SQL_CLUSTER_BALLAST,
      "billing": SQL_CLUSTER_BILLING,
      "collab": SQL_CLUSTER_COLLAB,
      "commits": SQL_CLUSTER_COMMITS,
      "configurations": SQL_CLUSTER_CONFIGURATIONS,
      "copilot": SQL_CLUSTER_COPILOT,
      "iam": SQL_CLUSTER_IAM,
      "iam_abilities": SQL_CLUSTER_IAM_ABILITIES,
      "issues-pull-requests": SQL_CLUSTER_ISSUES_PULL_REQUESTS,
      "lodge": SQL_CLUSTER_LODGE,
      "memex": SQL_CLUSTER_MEMEX,
      "mysql1": SQL_CLUSTER_MYSQL1,
      "mysql2": SQL_CLUSTER_MYSQL2,
      "mysql5": SQL_CLUSTER_MYSQL5,
      "notifications_deliveries": SQL_CLUSTER_NOTIFICATIONS_DELIVERIES,
      "notifications_entries": SQL_CLUSTER_NOTIFICATIONS_ENTRIES,
      "notifications_summaries": SQL_CLUSTER_NOTIFICATIONS_SUMMARIES,
      "notify": SQL_CLUSTER_NOTIFY,
      "octoshift": SQL_CLUSTER_OCTOSHIFT,
      "permissions": SQL_CLUSTER_PERMISSIONS,
      "repositories": SQL_CLUSTER_REPOSITORIES,
      "repositories-actions-checks": SQL_CLUSTER_REPOSITORIES_ACTIONS_CHECKS,
      "repositories-pushes-sharded": SQL_CLUSTER_REPOSITORIES_PUSHES_SHARDED,
      "security-overview": SQL_CLUSTER_SECURITY_OVERVIEW,
      "unknown": SQL_CLUSTER_UNKNOWN,
    }

    ON_PRIMARY_TRUE = "on_primary:true"
    ON_PRIMARY_FALSE = "on_primary:false"
    CACHED_TRUE = "cached:true"
    CACHED_FALSE = "cached:false"
    TYPE_READ = "type:read"
    TYPE_WRITE = "type:write"
    MUTATIONS_ON_READ_TRUE = "mutations_on_read:true"
    MUTATIONS_ON_READ_FALSE = "mutations_on_read:false"
    MUTATION_TRUE = "mutation:true"
    MUTATION_FALSE = "mutation:false"
    INTERNAL_ERROR_TRUE = "internal_error:true"
    INTERNAL_ERROR_FALSE = "internal_error:false"
    SUCCESS_TRUE = "success:true"
    SUCCESS_FALSE = "success:false"

    ORIGIN_API = "origin:api"
    ORIGIN_INTERNAL = "origin:internal"
    ORIGIN_MANUAL_EXECUTION = "origin:manual_execution"
    ORIGIN_REST_API = "origin:rest_api"

    ORIGINS = {
      "api": ORIGIN_API,
      "internal": ORIGIN_INTERNAL,
      "manual_execution": ORIGIN_MANUAL_EXECUTION,
      "rest_api": ORIGIN_REST_API,
    }

    OPERATION_TYPE_MUTATION = "operation_type:mutation"
    OPERATION_TYPE_QUERY = "operation_type:query"
    OPERATION_TYPE_SUBSCRIPTION = "operation_type:subscription"
    OPERATION_TYPE_UNKNOWN = "operation_type:unknown"

    OPERATION_TYPES = {
      mutation: OPERATION_TYPE_MUTATION,
      query: OPERATION_TYPE_QUERY,
      subscription: OPERATION_TYPE_SUBSCRIPTION,
      unknown: OPERATION_TYPE_UNKNOWN,
    }

    EXECUTION_TYPE_MAIN = "execution_type:main"
    EXECUTION_TYPE_DEFERRED_CHUNK = "execution_type:deferred_chunk"

    EXECUTION_TYPES = {
      "main": EXECUTION_TYPE_MAIN,
      "deferred_chunk": EXECUTION_TYPE_DEFERRED_CHUNK,
    }

    HTML_FILTER_COLONEMOJIFILTER = "filter:colonemojifilter"
    HTML_FILTER_UNICODEEMOJIFILTER = "filter:unicodeemojifilter"
    HTML_FILTER_ISSUEMENTIONFILTER = "filter:issuementionfilter"
    HTML_FILTER_MATHINLINEBACKTICKFILTER = "filter:mathinlinebacktickfilter"
    HTML_FILTER_MATHINLINEFILTER = "filter:mathinlinefilter"
    HTML_FILTER_COMMITMENTIONFILTER = "filter:commitmentionfilter"
    HTML_FILTER_ADVISORYMENTIONFILTER = "filter:advisorymentionfilter"
    HTML_FILTER_CVEMENTIONFILTER = "filter:cvementionfilter"
    HTML_FILTER_TEAMMENTIONFILTER = "filter:teammentionfilter"
    HTML_FILTER_MENTIONFILTER = "filter:mentionfilter"
    HTML_FILTER_TEXTDIRECTIONFILTER = "filter:textdirectionfilter"
    HTML_FILTER_RELNOFOLLOWFILTER = "filter:relnofollowfilter"
    HTML_FILTER_CLOSEKEYWORDFILTER = "filter:closekeywordfilter"
    HTML_FILTER_REFERENCE = "filter:reference"
    HTML_FILTER_MATHDISPLAYFILTER = "filter:mathdisplayfilter"
    HTML_FILTER_TASKLISTFILTER = "filter:tasklistfilter"
    HTML_FILTER_UTF8FILTER = "filter:utf8filter"
    HTML_FILTER_RELATIVELINKFILTER = "filter:relativelinkfilter"
    HTML_FILTER_VIDEOTAGFILTER = "filter:videotagfilter"
    HTML_FILTER_PLAINTEXTINPUTFILTER = "filter:plaintextinputfilter"
    HTML_FILTER_NOTRANSLATIONFILTER = "filter:notranslationfilter"
    HTML_FILTER_COLORFILTER = "filter:colorfilter"
    HTML_FILTER_LABELTAGFILTER = "filter:labeltagfilter"
    HTML_FILTER_ISSUEBLOBFILTER = "filter:issueblobfilter"
    HTML_FILTER_AUTOLINKFILTER = "filter:autolinkfilter"
    HTML_FILTER_DUPLICATEKEYWORDFILTER = "filter:duplicatekeywordfilter"
    HTML_FILTER_CUSTOMKEYLINKFILTER = "filter:customkeylinkfilter"
    HTML_FILTER_ALERTMENTIONFILTER = "filter:alertmentionfilter"
    HTML_FILTER_TABLEOFCONTENTSFILTER = "filter:tableofcontentsfilter"
    HTML_FILTER_MARKDOWNFILTER = "filter:markdownfilter"
    HTML_FILTER_CAMOFILTER = "filter:camofilter"
    HTML_FILTER_IMAGEMAXWIDTHFILTER = "filter:imagemaxwidthfilter"
    HTML_FILTER_ANIMATEDIMAGEFILTER = "filter:animatedimagefilter"
    HTML_FILTER_SYNTAXHIGHLIGHTFILTER = "filter:syntaxhighlightfilter"
    HTML_FILTER_SNIPPETCLIPBOARDCOPYFILTER = "filter:snippetclipboardcopyfilter"

    HTML_FILTERS = {
      colonemojifilter: HTML_FILTER_COLONEMOJIFILTER,
      unicodeemojifilter: HTML_FILTER_UNICODEEMOJIFILTER,
      issuementionfilter: HTML_FILTER_ISSUEMENTIONFILTER,
      mathinlinebacktickfilter: HTML_FILTER_MATHINLINEBACKTICKFILTER,
      mathinlinefilter: HTML_FILTER_MATHINLINEFILTER,
      commitmentionfilter: HTML_FILTER_COMMITMENTIONFILTER,
      advisorymentionfilter: HTML_FILTER_ADVISORYMENTIONFILTER,
      cvementionfilter: HTML_FILTER_CVEMENTIONFILTER,
      teammentionfilter: HTML_FILTER_TEAMMENTIONFILTER,
      mentionfilter: HTML_FILTER_MENTIONFILTER,
      textdirectionfilter: HTML_FILTER_TEXTDIRECTIONFILTER,
      relnofollowfilter: HTML_FILTER_RELNOFOLLOWFILTER,
      closekeywordfilter: HTML_FILTER_CLOSEKEYWORDFILTER,
      reference: HTML_FILTER_REFERENCE,
      mathdisplayfilter: HTML_FILTER_MATHDISPLAYFILTER,
      tasklistfilter: HTML_FILTER_TASKLISTFILTER,
      utf8filter: HTML_FILTER_UTF8FILTER,
      relativelinkfilter: HTML_FILTER_RELATIVELINKFILTER,
      videotagfilter: HTML_FILTER_VIDEOTAGFILTER,
      plaintextinputfilter: HTML_FILTER_PLAINTEXTINPUTFILTER,
      notranslationfilter: HTML_FILTER_NOTRANSLATIONFILTER,
      colorfilter: HTML_FILTER_COLORFILTER,
      labeltagfilter: HTML_FILTER_LABELTAGFILTER,
      issueblobfilter: HTML_FILTER_ISSUEBLOBFILTER,
      autolinkfilter: HTML_FILTER_AUTOLINKFILTER,
      duplicatekeywordfilter: HTML_FILTER_DUPLICATEKEYWORDFILTER,
      customkeylinkfilter: HTML_FILTER_CUSTOMKEYLINKFILTER,
      alertmentionfilter: HTML_FILTER_ALERTMENTIONFILTER,
      tableofcontentsfilter: HTML_FILTER_TABLEOFCONTENTSFILTER,
      markdownfilter: HTML_FILTER_MARKDOWNFILTER,
      camofilter: HTML_FILTER_CAMOFILTER,
      imagemaxwidthfilter: HTML_FILTER_IMAGEMAXWIDTHFILTER,
      animatedimagefilter: HTML_FILTER_ANIMATEDIMAGEFILTER,
      syntaxhighlightfilter: HTML_FILTER_SYNTAXHIGHLIGHTFILTER,
      snippetclipboardcopyfilter: HTML_FILTER_SNIPPETCLIPBOARDCOPYFILTER,
    }

    def initialize(tags)
      @tags_cache = {}

      tags.each do |tag_name, tag_value|
        @tags_cache[tag_name] = "#{tag_name}:#{tag_value}" unless tag_value.nil?
      end

      @pod_name = [@tags_cache[TaggingHelper::POD_NAME_TAG]].compact.freeze
      @controller_action = [
        @tags_cache[TaggingHelper::CONTROLLER_TAG],
        @tags_cache[TaggingHelper::ACTION_TAG],
      ].compact.freeze
      @method_controller_action_service = [
        @tags_cache[TaggingHelper::METHOD_TAG],
        @tags_cache[TaggingHelper::CATALOG_SERVICE_TAG],
        @tags_cache[TaggingHelper::CONTROLLER_TAG],
        @tags_cache[TaggingHelper::ACTION_TAG],
      ].compact.freeze
      @controller_action_service_method_status_category = [
        @tags_cache[TaggingHelper::STATUS_RANGE_TAG],
        @tags_cache[TaggingHelper::METHOD_TAG],
        @tags_cache[TaggingHelper::CATEGORY_TAG],
        @tags_cache[TaggingHelper::CATALOG_SERVICE_TAG],
        @tags_cache[TaggingHelper::CONTROLLER_TAG],
        @tags_cache[TaggingHelper::ACTION_TAG],
      ].compact.freeze
    end

    def [](tag_name)
      @tags_cache[tag_name]
    end
  end
end
