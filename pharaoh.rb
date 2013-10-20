# the rails booting process is described at http://apidock.com/rails/Rails/Application.
# From the moment you require config/application.rb in your app, the booting process goes like this:
# 1)  require config/boot.rb to setup load paths
# 2)  require railties and engines
# 3)  Define Rails.application as class MyApp::Application < Rails::Application
# 4)  Run config.before_configuration callbacks
# 5)  Load config/environments/ENV.rb
# 6)  Run config.before_initialize callbacks
# 7)  Run Railtie#initializer defined by railties, engines and application.
#     One by one, each engine sets up its load paths, routes and runs its config/initializers/* files.
# 9)  Custom Railtie#initializers added by railties, engines and applications are executed
# 10) Build the middleware stack and run to_prepare callbacks
# 11) Run config.before_eager_load and eager_load if cache classes is true
# 12) Run config.after_initialize callbacks
# Since every child process inherits environment variables from its parent, we can ensure
# that step 5 loads the correct environment file by setting the RAILS_ENV environment variable
# before requiring config/application.
ENV['RAILS_ENV'] = 'test'
require '../config/application'

# this call makes rails load activerecord and the like
Rails.application.require_environment!

# a child process inherits a copy of all open file descriptors belonging to the parent process.
# We don't want a child process accidentally sharing a database connection with the parent process,
# so we make sure to disconnent any connections.
ActiveRecord::Base.connection.disconnect!

# load rspec and disable autorun. Old version of rspec-rails generated a spec_helper file
# that included the line "require 'rspec/autorun'". This can cause specs to run twice if autorun
# is enabled. See https://github.com/jonleighton/spring/pull/98
require 'rspec'
RSpec::Core::Runner.disable_autorun!

# create a pipe that allows for communication between parent and child process. This pipe will
# be used to let the child process know when the parent is no longer there (this works even if
# the parent process gets killed with SIGKILL).
lifeline = IO.pipe

fork do
  # make the child process close its write endpoint of the pipe.
  # make the child process set sync to true for its read endpoint so as to avoid message buffering.
  lifeline[1].close
  lifeline[0].sync = true

  # this code makes the child process exit as soon as the parent is no longer active.
  # we create a thread that calls IO.select on its read endpoint. This is a blocking operation that
  # causes the thread to keep waiting. Note that the child process has already closed its write endpoint.
  # This means that only the main process has an open write endpoint to this pipe. So when the main process disappears,
  # the kernel detects nothing can write to this pipe anymore, and causes an EOF to be sent to the pipe. This EOF causes
  # IO.select to return, letting the child process know the parent process no longer exists.
  # Note that this works even when the parent process was killed with kill -9.
  lifeline_thread = Thread.new do
    result = IO.select([lifeline[0]])
    exit 1
  end

  ActiveRecord::Base.establish_connection
  filename = '../spec/controllers/admin/audits_controller_spec.rb'
  result = RSpec::Core::CommandLine.new(["-f", "p", filename]).run($stdout, $stderr)
end

# make parent process close its read endpoint of the pipe, as it has no use for it.
# The write endpoint is kept open in order for the lifeline mechanism to work. We also set sync to true so as to
# prevent message buffering.
lifeline[0].close
lifeline[1].sync = true
sleep 1000
