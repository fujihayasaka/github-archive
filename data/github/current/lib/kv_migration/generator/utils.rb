# typed: true
# frozen_string_literal: true

require "erubi"

module KvMigration
  module Generator
    module Utils
      include Kernel

      def load_template(template_path)
        template = File.read(template_path)
        Erubi::Engine.new(template).src
      end

      def write_file(file_path, content)
        File.open(file_path, "w") { |file| file.write(content) }
      end

      def ensure_directory_exists(directory_path)
        FileUtils.mkdir_p(directory_path)
      end

      def render(template_path, context)
        eval(load_template(template_path), binding) # rubocop:disable Security/Eval
      end
    end
  end
end
