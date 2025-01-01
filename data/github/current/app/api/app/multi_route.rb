# typed: true
# frozen_string_literal: true

# Port of Sinatra::MultiRoute for our usage.
# See https://github.com/sinatra/sinatra/blob/f716739811a0591ed1cc68f55fe92720f841fc19/sinatra-contrib/lib/sinatra/multi_route.rb
module Api::App::MultiRoute
  def head(*args, &block)     super(*route_args(args), &block)  end
  def delete(*args, &block)   super(*route_args(args), &block)  end
  def get(*args, &block)      super(*route_args(args), &block)  end
  def options(*args, &block)  super(*route_args(args), &block)  end
  def patch(*args, &block)    super(*route_args(args), &block)  end
  def post(*args, &block)     super(*route_args(args), &block)  end
  def put(*args, &block)      super(*route_args(args), &block)  end

  def route(*args, &block)
    options = args.last.is_a?(Hash) ? args.pop : {}
    routes = [*args.pop]
    args.each do |verb|
      verb = verb.to_s.upcase if verb.is_a?(Symbol)
      routes.each do |route|
        super(verb, route, options, &block)
      end
    end
  end

  private

  def route_args(args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    [args, options]
  end
end
