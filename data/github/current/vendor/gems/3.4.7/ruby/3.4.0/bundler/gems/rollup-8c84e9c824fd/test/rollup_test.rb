require "test_helper"

class RollupTest < Minitest::Test
  def test_maintains_rollup_across_line_number_changes
    bt1 = ["blah.rb:2:in `foo'", "blah.rb:1:in `bar'"]
    bt2 = ["blah.rb:4:in `foo'", "blah.rb:3:in `bar'"]

    rollup1, rollup2 = [bt1, bt2].map do |backtrace|
      exc = StandardError.new
      exc.set_backtrace(backtrace)
      Rollup.generate(exc)
    end

    assert_equal rollup1, rollup2
  end

  def test_maintains_rollup_across_erb_method_name_changes_from_blocks
    bt1 = ["/build/app/views/mailers/billing_notifications/manual_dunning_attempts.html.erb:34:in `block (3 levels) in _app_views_mailers_billing_notifications_manual_dunning_attempts_html_erb___2653670918992827342_2264720'"]
    bt2 = ["/build/app/views/mailers/billing_notifications/manual_dunning_attempts.html.erb:34:in `block (3 levels) in _app_views_mailers_billing_notifications_manual_dunning_attempts_html_erb___1334592852714817929_2179560'"]

    rollup1, rollup2 = [bt1, bt2].map do |backtrace|
      exc = StandardError.new
      exc.set_backtrace(backtrace)
      Rollup.generate(exc)
    end

    assert_equal rollup1, rollup2
  end

  def test_maintains_rollup_across_ERB_generated_method_name_changes
    bt1 = ["app/views/layouts/_repository_container.html.erb:3:in `_app_views_layouts__repository_container_html_erb___3183776605944482718_70332203429960'"]
    bt2 = ["app/views/layouts/_repository_container.html.erb:3:in `_app_views_layouts__repository_container_html_erb__1622937568524016425_70278849449260'"]

    rollup1, rollup2 = [bt1, bt2].map do |backtrace|
      exc = StandardError.new
      exc.set_backtrace(backtrace)
      Rollup.generate(exc)
    end

    assert_equal rollup1, rollup2
  end

  def test_maintains_rollup_across_actionview_generated_method_name_changes
    bt1 = ["app/views/layouts/_repository_container.html.erb:3:in `_app_views_gists_listings_feed_atom_builder___3183776605944482718_70332203429960'"]
    bt2 = ["app/views/layouts/_repository_container.html.erb:3:in `_app_views_gists_listings_feed_atom_builder___1622937568524016425_70278849449260'"]

    rollup1, rollup2 = [bt1, bt2].map do |backtrace|
      exc = StandardError.new
      exc.set_backtrace(backtrace)
      Rollup.generate(exc)
    end

    assert_equal rollup1, rollup2
  end

  def test_handles_empty_backtrace
    exc = StandardError.new
    rollup = Rollup.generate(exc)
    refute_nil rollup
  end

  def test_handles_unlikely_backtrace_where_all_frames_are_denylisted
    exc = StandardError.new
    exc.set_backtrace(["vendor/blah.rb:123", "vendor/mmhmm.rb:123"])
    rollup = Rollup.generate(exc)
    refute_nil rollup
  end

  def test_differentiates_between_GitRPC_Timeout_problems
    # Needed for these two backtraces to be differentiated
    denylist = ["vendor/",
                 "config/ernicorn.rb",
                 "bin/ernicorn",
                 "THE WIRE",
                 "app/models/repository/spawn_dependency.rb"]
    Rollup.denylist = denylist

    problem_1_bt = <<-EOF.strip.split("\n")
      /data/github/current/vendor/gitrpc/lib/gitrpc/backend/spawn.rb:87:in `rescue in spawn'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend/spawn.rb:82:in `spawn'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend/spawn.rb:96:in `spawn_git'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend/spawn.rb:105:in `spawn_git_ro'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend.rb:128:in `block (2 levels) in send_message'\n/data/github/current/vendor/ruby/b3255a8b572160bf249b5019c1ec93e667d547ee/lib/ruby/2.1.0/timeout.rb:90:in `block in timeout'\n/data/github/current/vendor/ruby/b3255a8b572160bf249b5019c1ec93e667d547ee/lib/ruby/2.1.0/timeout.rb:100:in `call'\n/data/github/current/vendor/ruby/b3255a8b572160bf249b5019c1ec93e667d547ee/lib/ruby/2.1.0/timeout.rb:100:in `timeout'\n/data/github/current/vendor/gitrpc/lib/gitrpc/timer.rb:48:in `timeout'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend.rb:126:in `block in send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/gitmon_client.rb:37:in `track'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend.rb:125:in `send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol/bertrpc.rb:134:in `send_message'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn.rb:91:in `call'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn.rb:91:in `dispatch'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn.rb:164:in `process'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn/server.rb:53:in `process_ernicorn_client'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn/server.rb:41:in `block in process_client'\n/data/github/current/config/ernicorn.rb:53:in `around_filter'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn/server.rb:41:in `process_client'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:670:in `worker_loop'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn/server.rb:34:in `worker_loop'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:525:in `spawn_missing_workers'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:140:in `start'\n/data/github/current/vendor/internal-gems/ernicorn/script/ernicorn:68:in `<top (required)>'\nbin/ernicorn:3:in `load'\nbin/ernicorn:3:in `<main>'\n---- THE WIRE ----\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol/bertrpc.rb:97:in `send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol/chimney_transitional.rb:34:in `block in send_message'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `block in instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications/instrumenter.rb:20:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `instrument'\n/data/github/current/vendor/gitrpc/lib/gitrpc.rb:198:in `instrument'\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol/chimney_transitional.rb:33:in `send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol.rb:99:in `call'\n/data/github/current/vendor/gitrpc/lib/gitrpc/middleware/ensure_valid_call.rb:13:in `call'\n/data/github/current/vendor/gitrpc/lib/gitrpc/middleware/instrumentation.rb:10:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `block in instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications/instrumenter.rb:20:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `instrument'\n/data/github/current/vendor/gitrpc/lib/gitrpc.rb:198:in `instrument'\n/data/github/current/vendor/gitrpc/lib/gitrpc/middleware/instrumentation.rb:9:in `call'\n/data/github/current/vendor/gitrpc/lib/gitrpc/middleware.rb:25:in `method_missing'\n/data/github/current/vendor/gitrpc/lib/gitrpc/client.rb:104:in `send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/client/spawn.rb:83:in `spawn_git'\n/data/github/current/app/models/repository/spawn_dependency.rb:79:in `git_command'\n/data/github/current/app/models/repository.rb:1398:in `block (2 levels) in shortlog'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `block in instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications/instrumenter.rb:20:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `instrument'\n/data/github/current/lib/github/config/notifications.rb:24:in `instrument'\n/data/github/current/app/models/repository.rb:1397:in `block in shortlog'\n/data/github/current/lib/github/cache/utils.rb:35:in `fetch'\n/data/github/current/lib/github/cache/client.rb:16:in `block in fetch'\n/data/github/current/lib/github/cache_leak_detector.rb:27:in `caching'\n/data/github/current/lib/github/cache/client.rb:15:in `fetch'\n/data/github/current/app/models/repository.rb:1396:in `shortlog'\n/data/github/current/app/models/repository.rb:1410:in `contribution_counts'\n/data/github/current/app/models/repository.rb:1365:in `contributors'\n/data/github/current/app/models/repository.rb:1341:in `block in contributors_size'\n/data/github/current/lib/github/cache/utils.rb:35:in `fetch'\n/data/github/current/lib/github/cache/client.rb:16:in `block in fetch'\n/data/github/current/lib/github/cache_leak_detector.rb:27:in `caching'\n/data/github/current/lib/github/cache/client.rb:15:in `fetch'\n/data/github/current/app/models/repository.rb:1340:in `contributors_size'\n/data/github/current/app/views/files/_contributors_size.html.erb:5:in `block in _app_views_files__contributors_size_html_erb__3426383246830401527_69891512221360'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/helpers/cache_helper.rb:53:in `fragment_for'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/helpers/cache_helper.rb:36:in `cache'\n/data/github/current/app/helpers/application_helper.rb:7:in `block in cache'\n/data/github/current/lib/github/cache_leak_detector.rb:27:in `caching'\n/data/github/current/app/helpers/application_helper.rb:6:in `cache'\n/data/github/current/app/views/files/_contributors_size.html.erb:1:in `_app_views_files__contributors_size_html_erb__3426383246830401527_69891512221360'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/template.rb:145:in `block in render'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `block in instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications/instrumenter.rb:20:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/template.rb:143:in `render'\n/data/github/current/config/instrumentation.rb:186:in `render_with_timing'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/renderer/partial_renderer.rb:265:in `render_partial'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/renderer/partial_renderer.rb:238:in `block in render'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/renderer/abstract_renderer.rb:38:in `block in instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `block in instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications/instrumenter.rb:20:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/renderer/abstract_renderer.rb:38:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/renderer/partial_renderer.rb:237:in `render'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/renderer/renderer.rb:41:in `render_partial'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_view/renderer/renderer.rb:15:in `render'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/abstract_controller/rendering.rb:110:in `_render_template'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/streaming.rb:225:in `_render_template'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/abstract_controller/rendering.rb:103:in `render_to_body'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/renderers.rb:28:in `render_to_body'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/compatibility.rb:50:in `render_to_body'\n/data/github/current/app/controllers/application_controller.rb:172:in `render_to_body'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/abstract_controller/rendering.rb:88:in `render'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/rendering.rb:16:in `render'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/instrumentation.rb:40:in `block (2 levels) in render'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/core_ext/benchmark.rb:5:in `block in ms'\n/data/github/current/vendor/ruby/b3255a8b572160bf249b5019c1ec93e667d547ee/lib/ruby/2.1.0/benchmark.rb:294:in `realtime'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/core_ext/benchmark.rb:5:in `ms'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/instrumentation.rb:40:in `block in render'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/instrumentation.rb:83:in `cleanup_view_runtime'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activerecord-3.2.21.github6/lib/active_record/railties/controller_runtime.rb:24:in `cleanup_view_runtime'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/instrumentation.rb:39:in `render'\n/data/github/current/app/controllers/application_controller.rb:1023:in `render'\n/data/github/current/app/controllers/repositories_controller.rb:137:in `block (2 levels) in contributors_size'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/mime_responds.rb:196:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/mime_responds.rb:196:in `respond_to'\n/data/github/current/app/controllers/repositories_controller.rb:135:in `contributors_size'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/implicit_render.rb:4:in `send_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/abstract_controller/base.rb:167:in `process_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/rendering.rb:10:in `process_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/abstract_controller/callbacks.rb:18:in `block in process_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:696:in `block (7 levels) in _run__724516071108631026__process_action__3676444548082723252__callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:215:in `block in _conditional_callback_around_8166'\n/data/github/current/app/controllers/application_controller/feature_flags_dependency.rb:19:in `enable_feature_flags'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:214:in `_conditional_callback_around_8166'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:574:in `block (6 levels) in _run__724516071108631026__process_action__3676444548082723252__callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:215:in `block in _conditional_callback_around_8165'\n/data/github/current/app/controllers/application_controller/stats_dependency.rb:45:in `staff_external_service_profiler'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:214:in `_conditional_callback_around_8165'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:573:in `block (5 levels) in _run__724516071108631026__process_action__3676444548082723252__callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:215:in `block in _conditional_callback_around_8164'\n/data/github/current/app/controllers/application_controller/stats_dependency.rb:31:in `staff_rails_instrumentation'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:214:in `_conditional_callback_around_8164'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:572:in `block (4 levels) in _run__724516071108631026__process_action__3676444548082723252__callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:215:in `block in _conditional_callback_around_8163'\n/data/github/current/app/controllers/application_controller.rb:485:in `setup_request_context'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:214:in `_conditional_callback_around_8163'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:417:in `block (3 levels) in _run__724516071108631026__process_action__3676444548082723252__callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:215:in `block in _conditional_callback_around_8162'\n/data/github/current/app/controllers/application_controller/database_dependency.rb:24:in `block in select_default_database'\n/data/github/current/lib/github/config/mysql.rb:72:in `block (2 levels) in use_alternate_db'\n/data/github/current/lib/github/config/mysql.rb:86:in `block in wrap_with_newsies_method'\n/data/github/current/lib/newsies/connection.rb:55:in `block in use_readonly_db'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activerecord-3.2.21.github6/lib/active_record/connection_adapters/abstract/query_cache.rb:26:in `cache'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activerecord-3.2.21.github6/lib/active_record/query_cache.rb:10:in `cache'\n/data/github/current/lib/newsies/connection.rb:54:in `use_readonly_db'\n/data/github/current/lib/newsies/connection.rb:63:in `use_db_based_on_github_alternate'\n/data/github/current/lib/github/config/mysql.rb:86:in `wrap_with_newsies_method'\n/data/github/current/lib/github/config/mysql.rb:71:in `block in use_alternate_db'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activerecord-3.2.21.github6/lib/active_record/connection_adapters/abstract/query_cache.rb:26:in `cache'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activerecord-3.2.21.github6/lib/active_record/query_cache.rb:10:in `cache'\n/data/github/current/lib/github/config/mysql.rb:70:in `use_alternate_db'\n/data/github/current/app/controllers/application_controller/database_dependency.rb:23:in `select_default_database'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:214:in `_conditional_callback_around_8162'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:416:in `block (2 levels) in _run__724516071108631026__process_action__3676444548082723252__callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:215:in `block in _conditional_callback_around_8161'\n/data/github/current/app/controllers/application_controller.rb:123:in `enable_read_only_mode'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:214:in `_conditional_callback_around_8161'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:415:in `block in _run__724516071108631026__process_action__3676444548082723252__callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:215:in `block in _conditional_callback_around_8160'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/marginalia-1.1.4/lib/marginalia/railtie.rb:30:in `record_query_comment'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:214:in `_conditional_callback_around_8160'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:414:in `_run__724516071108631026__process_action__3676444548082723252__callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:405:in `__run_callback'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:385:in `_run_process_action_callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:81:in `run_callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/abstract_controller/callbacks.rb:17:in `process_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/rescue.rb:29:in `process_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/instrumentation.rb:30:in `block in process_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `block in instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications/instrumenter.rb:20:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/instrumentation.rb:29:in `process_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/params_wrapper.rb:207:in `process_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activerecord-3.2.21.github6/lib/active_record/railties/controller_runtime.rb:18:in `process_action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/abstract_controller/base.rb:121:in `process'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/abstract_controller/rendering.rb:45:in `process'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal.rb:203:in `dispatch'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal/rack_delegation.rb:14:in `dispatch'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_controller/metal.rb:246:in `block in action'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/routing/route_set.rb:73:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/routing/route_set.rb:73:in `dispatch'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/routing/route_set.rb:36:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/journey-1.0.4/lib/journey/router.rb:68:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/journey-1.0.4/lib/journey/router.rb:56:in `each'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/journey-1.0.4/lib/journey/router.rb:56:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/routing/route_set.rb:608:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/best_standards_support.rb:17:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/etag.rb:24:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/conditionalget.rb:25:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/head.rb:14:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/params_parser.rb:21:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/flash.rb:259:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/session/abstract/id.rb:225:in `context'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/session/abstract/id.rb:220:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/cookies.rb:344:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activerecord-3.2.21.github6/lib/active_record/connection_adapters/abstract/connection_pool.rb:479:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/callbacks.rb:28:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:405:in `_run__4160251999181832371__call__3887846647347153281__callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:405:in `__run_callback'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:385:in `_run_call_callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/callbacks.rb:81:in `run_callbacks'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/callbacks.rb:27:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/debug_exceptions.rb:16:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/show_exceptions.rb:56:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/railties-3.2.21.github6/lib/rails/rack/logger.rb:32:in `call_app'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/railties-3.2.21.github6/lib/rails/rack/logger.rb:16:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/tagged_logging.rb:22:in `tagged'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/railties-3.2.21.github6/lib/rails/rack/logger.rb:16:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/actionpack-3.2.21.github6/lib/action_dispatch/middleware/request_id.rb:22:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/methodoverride.rb:22:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/runtime.rb:18:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/railties-3.2.21.github6/lib/rails/engine.rb:484:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/railties-3.2.21.github6/lib/rails/application.rb:232:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/railties-3.2.21.github6/lib/rails/railtie/configurable.rb:30:in `method_missing'\n/data/github/current/lib/github/limiters/middleware.rb:94:in `call'\n/data/github/current/lib/github/limiters/middleware.rb:94:in `call'\n/data/github/current/lib/github/safari_cookie_strip_middleware.rb:17:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/urlmap.rb:66:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/urlmap.rb:50:in `each'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/urlmap.rb:50:in `call'\n/data/github/current/lib/github/routers.rb:32:in `call'\n/data/github/current/lib/github/limiters/renderer.rb:16:in `call'\n/data/github/current/app/models/experiment_cache.rb:8:in `block in call'\n/data/github/current/app/models/experiment_cache.rb:29:in `enable'\n/data/github/current/app/models/experiment_cache.rb:8:in `call'\n/data/github/current/app/models/permission_cache.rb:11:in `block in call'\n/data/github/current/app/models/permission_cache.rb:32:in `enable'\n/data/github/current/app/models/permission_cache.rb:11:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activerecord-3.2.21.github6/lib/active_record/query_cache.rb:64:in `call'\n/data/github/current/lib/flipper/middleware/overrider.rb:62:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/flipper-0.7.0.beta1.5.gc3412e5/lib/flipper/middleware/memoizer.rb:40:in `call'\n/data/github/current/lib/rack/request_logger.rb:20:in `call'\n/data/github/current/lib/rack/request_id.rb:20:in `call'\n/data/github/current/lib/rack/server_id.rb:16:in `call'\n/data/github/current/lib/rack/content_type_cleaner.rb:11:in `call'\n/data/github/current/lib/rack/malformed_request_handler.rb:10:in `call'\n/data/github/current/lib/rack/security_headers.rb:41:in `call'\n/data/github/current/lib/github/timeout_middleware.rb:125:in `call'\n/data/github/current/lib/github/request_timer_middleware.rb:12:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/urlmap.rb:66:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/urlmap.rb:50:in `each'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/urlmap.rb:50:in `call'\n/data/github/current/lib/github/cache/reset_middleware.rb:9:in `call'\n/data/github/current/lib/rack/process_utilization.rb:866:in `call'\n/data/github/current/lib/unicorn/kill_introspect_worker.rb:66:in `call'\n/data/github/current/lib/github/flamegraph_middleware.rb:15:in `call'\n/data/github/current/lib/github/line_profiler_middleware.rb:16:in `call'\n/data/github/current/lib/github/weak_etag_middleware.rb:24:in `call'\n/data/github/current/lib/github/invalid_parameters_middleware.rb:9:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/failbot-1.2.0/lib/failbot/middleware.rb:16:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/failbot-1.2.0/lib/failbot.rb:113:in `push'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/failbot-1.2.0/lib/failbot/middleware.rb:13:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/config.rb:17:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:576:in `process_client'\n/data/github/current/lib/github/unicorn/oob_gc.rb:72:in `process_client'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:670:in `worker_loop'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:525:in `spawn_missing_workers'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:536:in `maintain_worker_count'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:294:in `join'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/bin/unicorn_rails:209:in `<top (required)>'\n/data/github/current/bin/unicorn_rails:3:in `load'\n/data/github/current/bin/unicorn_rails:3:in `<main>'
    EOF

    problem_2_bt = <<-EOF.strip.split("\n")
      /data/github/current/vendor/gitrpc/lib/gitrpc/backend/spawn.rb:87:in `rescue in spawn'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend/spawn.rb:82:in `spawn'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend/spawn.rb:96:in `spawn_git'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend.rb:128:in `block (2 levels) in send_message'\n/data/github/current/vendor/ruby/b3255a8b572160bf249b5019c1ec93e667d547ee/lib/ruby/2.1.0/timeout.rb:90:in `block in timeout'\n/data/github/current/vendor/ruby/b3255a8b572160bf249b5019c1ec93e667d547ee/lib/ruby/2.1.0/timeout.rb:100:in `call'\n/data/github/current/vendor/ruby/b3255a8b572160bf249b5019c1ec93e667d547ee/lib/ruby/2.1.0/timeout.rb:100:in `timeout'\n/data/github/current/vendor/gitrpc/lib/gitrpc/timer.rb:48:in `timeout'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend.rb:126:in `block in send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/gitmon_client.rb:37:in `track'\n/data/github/current/vendor/gitrpc/lib/gitrpc/backend.rb:125:in `send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol/bertrpc.rb:134:in `send_message'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn.rb:91:in `call'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn.rb:91:in `dispatch'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn.rb:164:in `process'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn/server.rb:53:in `process_ernicorn_client'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn/server.rb:41:in `block in process_client'\n/data/github/current/config/ernicorn.rb:53:in `around_filter'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn/server.rb:41:in `process_client'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:670:in `worker_loop'\n/data/github/current/vendor/internal-gems/ernicorn/lib/ernicorn/server.rb:34:in `worker_loop'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:525:in `spawn_missing_workers'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:140:in `start'\n/data/github/current/vendor/internal-gems/ernicorn/script/ernicorn:68:in `<top (required)>'\nbin/ernicorn:3:in `load'\nbin/ernicorn:3:in `<main>'\n---- THE WIRE ----\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol/bertrpc.rb:97:in `send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol/chimney_transitional.rb:34:in `block in send_message'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `block in instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications/instrumenter.rb:20:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `instrument'\n/data/github/current/vendor/gitrpc/lib/gitrpc.rb:198:in `instrument'\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol/chimney_transitional.rb:33:in `send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/protocol.rb:99:in `call'\n/data/github/current/vendor/gitrpc/lib/gitrpc/middleware/ensure_valid_call.rb:13:in `call'\n/data/github/current/vendor/gitrpc/lib/gitrpc/middleware/instrumentation.rb:10:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `block in instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications/instrumenter.rb:20:in `instrument'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activesupport-3.2.21.github6/lib/active_support/notifications.rb:123:in `instrument'\n/data/github/current/vendor/gitrpc/lib/gitrpc.rb:198:in `instrument'\n/data/github/current/vendor/gitrpc/lib/gitrpc/middleware/instrumentation.rb:9:in `call'\n/data/github/current/vendor/gitrpc/lib/gitrpc/middleware.rb:25:in `method_missing'\n/data/github/current/vendor/gitrpc/lib/gitrpc/client.rb:104:in `send_message'\n/data/github/current/vendor/gitrpc/lib/gitrpc/client/spawn.rb:83:in `spawn_git'\n/data/github/current/app/models/repository/spawn_dependency.rb:79:in `git_command'\n/data/github/current/app/models/commits_collection.rb:298:in `create_merge_commit'\n/data/github/current/app/models/ref.rb:647:in `block in merge'\n/data/github/current/app/models/ref.rb:738:in `block in retrying'\n/data/github/current/app/models/ref.rb:736:in `upto'\n/data/github/current/app/models/ref.rb:736:in `each'\n/data/github/current/app/models/ref.rb:736:in `retrying'\n/data/github/current/app/models/ref.rb:646:in `merge'\n/data/github/current/app/api/repos.rb:529:in `block in <class:Repos>'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:1213:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:1213:in `block in compile!'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:786:in `[]'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:786:in `block (3 levels) in route!'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:802:in `route_eval'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:786:in `block (2 levels) in route!'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:823:in `block in process_route'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:821:in `catch'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:821:in `process_route'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:784:in `block in route!'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:783:in `each'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:783:in `route!'\n/data/github/current/app/api/app/rate_limit_dependency.rb:72:in `block in dispatch!'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:872:in `block in invoke'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:872:in `catch'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:872:in `invoke'\n/data/github/current/app/api/app/rate_limit_dependency.rb:69:in `dispatch!'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:719:in `block in call!'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:872:in `block in invoke'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:872:in `catch'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:872:in `invoke'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:719:in `call!'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:705:in `call'\n/data/github/current/app/api/middleware/silence_events_and_notifications_blacklist.rb:26:in `call'\n/data/github/current/app/api/middleware/database_selection.rb:23:in `call'\n/data/github/current/app/api/middleware/cors.rb:50:in `call'\n/data/github/current/app/api/middleware/enforce_media_type.rb:29:in `call'\n/data/github/current/lib/github/limiters/middleware.rb:94:in `call'\n/data/github/current/app/api/middleware/request_authentication_fingerprint.rb:28:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/nulllogger.rb:9:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/head.rb:13:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:1338:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:1420:in `synchronize'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/sinatra-1.3.2.github/lib/sinatra/base.rb:1338:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/conditionalget.rb:38:in `call'\n/data/github/current/lib/github/routers.rb:32:in `call'\n/data/github/current/lib/github/limiters/renderer.rb:16:in `call'\n/data/github/current/app/models/experiment_cache.rb:8:in `block in call'\n/data/github/current/app/models/experiment_cache.rb:29:in `enable'\n/data/github/current/app/models/experiment_cache.rb:8:in `call'\n/data/github/current/app/models/permission_cache.rb:11:in `block in call'\n/data/github/current/app/models/permission_cache.rb:32:in `enable'\n/data/github/current/app/models/permission_cache.rb:11:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/activerecord-3.2.21.github6/lib/active_record/query_cache.rb:64:in `call'\n/data/github/current/lib/flipper/middleware/overrider.rb:62:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/flipper-0.7.0.beta1.5.gc3412e5/lib/flipper/middleware/memoizer.rb:40:in `call'\n/data/github/current/lib/rack/request_logger.rb:20:in `call'\n/data/github/current/lib/rack/request_id.rb:20:in `call'\n/data/github/current/lib/rack/server_id.rb:16:in `call'\n/data/github/current/lib/rack/content_type_cleaner.rb:11:in `call'\n/data/github/current/lib/rack/malformed_request_handler.rb:10:in `call'\n/data/github/current/lib/rack/security_headers.rb:41:in `call'\n/data/github/current/lib/github/timeout_middleware.rb:125:in `call'\n/data/github/current/lib/github/request_timer_middleware.rb:12:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/urlmap.rb:66:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/urlmap.rb:50:in `each'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/urlmap.rb:50:in `call'\n/data/github/current/lib/github/cache/reset_middleware.rb:9:in `call'\n/data/github/current/lib/rack/process_utilization.rb:866:in `call'\n/data/github/current/lib/unicorn/kill_introspect_worker.rb:66:in `call'\n/data/github/current/lib/github/flamegraph_middleware.rb:15:in `call'\n/data/github/current/lib/github/line_profiler_middleware.rb:16:in `call'\n/data/github/current/lib/github/weak_etag_middleware.rb:24:in `call'\n/data/github/current/lib/github/invalid_parameters_middleware.rb:9:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/failbot-1.2.0/lib/failbot/middleware.rb:16:in `block in call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/failbot-1.2.0/lib/failbot.rb:113:in `push'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/failbot-1.2.0/lib/failbot/middleware.rb:13:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/rack-1.6.4/lib/rack/config.rb:17:in `call'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:576:in `process_client'\n/data/github/current/lib/github/unicorn/oob_gc.rb:72:in `process_client'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:670:in `worker_loop'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:525:in `spawn_missing_workers'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/lib/unicorn/http_server.rb:140:in `start'\n/data/github/current/vendor/gems/2.1.7/ruby/2.1.0/gems/unicorn-4.8.3/bin/unicorn_rails:209:in `<top (required)>'\n/data/github/current/bin/unicorn_rails:3:in `load'\n/data/github/current/bin/unicorn_rails:3:in `<main>'
    EOF

    rollup1, rollup2 = [problem_1_bt, problem_2_bt].map do |backtrace|
      exc = Exception.new
      exc.set_backtrace(backtrace)
      Rollup.generate(exc)
    end

    refute_equal rollup1, rollup2
  end

  def test_scrubs_root_path
    standard_bt = ["/data/github/current/app/models/user.rb:12345:in `boom'"]
    scrubbed_bt = ["/app/models/user.rb:12345:in `boom'"]

    standard_exc = StandardError.new
    standard_exc.set_backtrace(standard_bt)

    scrubbed_exc = StandardError.new
    scrubbed_exc.set_backtrace(scrubbed_bt)

    assert_equal Rollup.generate(standard_exc, scrub_root_path: "/data/github/current"),
                 Rollup.generate(scrubbed_exc)

    refute_equal Rollup.generate(standard_exc),
                 Rollup.generate(scrubbed_exc)
  end

  def test_setting_custom_denylist
    bt1 = ["/lib/github/rollup.rb:12345:in `boom'",
           "/app/models/user.rb:67890:in `something'"]
    exc1 = StandardError.new
    exc1.set_backtrace(bt1)

    bt2 = ["/app/models/user.rb:67890:in `something'"]
    exc2 = StandardError.new
    exc2.set_backtrace(bt2)

    refute_equal Rollup.generate(exc1), Rollup.generate(exc2)

    Rollup.denylist = ["lib/github/"]

    assert_equal Rollup.generate(exc1), Rollup.generate(exc2)
  end

  def test_setting_custom_denylist_fails_given_nonstrings
    assert_raises(ArgumentError) do
      Rollup.denylist = ["lib/github/", 1]
    end
  end

  def test_setting_custom_denylist_with_old_method
    bt1 = ["/lib/github/rollup.rb:12345:in `boom'",
           "/app/models/user.rb:67890:in `something'"]
    exc1 = StandardError.new
    exc1.set_backtrace(bt1)

    bt2 = ["/app/models/user.rb:67890:in `something'"]
    exc2 = StandardError.new
    exc2.set_backtrace(bt2)

    refute_equal Rollup.generate(exc1), Rollup.generate(exc2)

    Rollup.set_custom_blacklist(["lib/github/"])

    assert_equal Rollup.generate(exc1), Rollup.generate(exc2)
  end

  def test_setting_custom_denylist_with_old_method_fails_given_nonstrings
    assert_raises(ArgumentError) do
      Rollup.set_custom_blacklist(["lib/github/", 1])
    end
  end

  def test_first_significant_frame_returns_empty_string_for_nil_or_empty
    assert_equal "", Rollup.first_significant_frame(nil)
    assert_equal "", Rollup.first_significant_frame([])
  end

  def test_first_significant_frame_returns_first_frame_when_all_denylisted
    Rollup.denylist = ["vendor/"]
    backtrace = ["vendor/blah.rb:123", "vendor/mmhmm.rb:123"]
    assert_equal backtrace[0], Rollup.first_significant_frame(backtrace)
  end

  def test_first_significant_frame_returns_first_significant_frame
    Rollup.denylist = ["vendor/"]
    backtrace = [
      "vendor/blah.rb:123",
      "vendor/mmhmm.rb:123",
      "/data/github/current/app/models/user.rb:12345:in `boom'",
      "/data/github/current/app/models/repository.rb:890:in `bang'",
    ]
    assert_equal backtrace[2], Rollup.first_significant_frame(backtrace)
  end

  def test_first_significant_frame_scrubs_root_path
    Rollup.denylist = ["vendor/"]
    backtrace = [
      "vendor/blah.rb:123",
      "vendor/mmhmm.rb:123",
      "/data/github/current/app/models/user.rb:12345:in `boom'",
      "/data/github/current/app/models/repository.rb:890:in `bang'",
    ]
    scrubbed_frame = "app/models/user.rb:12345:in `boom'"
    assert_equal scrubbed_frame, Rollup.first_significant_frame(backtrace, scrub_root_path: "/data/github/current/")
  end

  def test_significant_returns_false_for_denylisted_frames
    Rollup.denylist = ["vendor/"]
    refute Rollup.significant?("vendor/blah.rb:123")
    refute Rollup.significant?("vendor/mmhmm.rb:123")
  end

  def test_significant_returns_true_for_undenylisted_frames
    Rollup.denylist = ["vendor/"]
    assert Rollup.significant?("/data/github/current/app/models/user.rb:12345:in `boom'")
    assert Rollup.significant?("/data/github/current/app/models/repository.rb:890:in `bang'")
  end

  def test_method_is_used_in_rollup_when_present
    bt1 = ["/data/github/current/app/models/user.rb:12345:in `boom'"]
    bt2 = ["/data/github/current/app/models/user.rb:12345:in `wow'"]

    rollup1, rollup2 = [bt1, bt2].map do |backtrace|
      exc = StandardError.new
      exc.set_backtrace(backtrace)
      Rollup.generate(exc)
    end

    refute_equal rollup1, rollup2
  end

  def boom!
    raise "Boom!"
  end

  def bang!
    raise "Bang!"
  end

  module Bang
    def self.bang!
      raise "Bang!"
    end
  end

  class Cannon
    def bang!
      raise "Bang!"
    end
  end

  def rescue_and_rollup
    begin
      yield
    rescue => e
      Rollup.generate(e)
    end
  end

  def test_rollup_considers_method_name
    boom_rollup = rescue_and_rollup { boom! }
    bang_rollup = rescue_and_rollup { bang! }

    refute_equal boom_rollup, bang_rollup
  end

  # This is not really the desired behavior, but we're preserving it for now for
  # compatibility (the method owner was added in Ruby 3.4).
  def test_rollup_ignores_method_owner_name
    bang_rollup = rescue_and_rollup { bang! }
    module_bang_rollup = rescue_and_rollup { Bang.bang! }
    instance_bang_rollup = rescue_and_rollup { Cannon.new.bang! }

    assert_equal bang_rollup, module_bang_rollup
    assert_equal bang_rollup, instance_bang_rollup
  end

  def teardown
    Rollup.denylist = []
  end
end
