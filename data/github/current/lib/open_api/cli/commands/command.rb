# typed: false
# frozen_string_literal: true

require "active_support/core_ext/module/delegation"

module OpenApi
  module CLI
    module Commands
      class Command
        delegate :ask, :yes?, to: :@shell

        def self.run(shell, *args, **kwargs)
          new(shell).run(*args, **kwargs)
        end

        def initialize(shell)
          @shell = shell
        end

        def nl
          $stderr.puts
        end

        def say(message = "", *colors)
          if colors.empty?
            colors = [:white]
          end
          buffer = @shell.set_color(message, *colors)
          $stderr.puts(buffer)
        end

        def ask(message, *colors)
          if colors.empty?
            colors = [:white]
          end
          buffer = @shell.set_color(message + ": ", *colors)
          $stderr.print(buffer)
          $stdin.gets.strip
        end

        def prefix(message, color = :white)
          buffer = @shell.set_color(message, color)
          $stderr.write(buffer)
        end
      end
    end
  end
end
