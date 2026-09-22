# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
threads threads_count, threads_count

rails_env = ENV.fetch("RAILS_ENV", "development")

if rails_env == "production"
  # Render sets WEB_CONCURRENCY. With a single worker we still preload the app
  # so boot happens once and copy-on-write is available if workers are added.
  worker_count = Integer(ENV.fetch("WEB_CONCURRENCY", 1))
  if worker_count > 1
    workers worker_count
  else
    preload_app!
  end
end

# shopinfo.app (web_scraper) owns localhost:3000 in dev, so we default to 3001
# here. PORT env var still wins (Render sets it in production).
port ENV.fetch("PORT", 3001)

# Specifies the `environment` that Puma will run in.
environment rails_env

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
