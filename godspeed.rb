#   Ruby 1.9.3-p125

require 'pathname'

##################################################################################
# get the app path and name
app_path = Pathname.new(Dir.pwd).expand_path
appname  = app_path.basename.to_s

##################################################################################
# Determine if a database has been selected
database = File.exists?(app_path.join('config/database.yml'))

##################################################################################
# remove some files we don't need
['README.rdoc', 'public/index.html', 'public/favicon.ico', 'app/assets/images/rails.png'].each do |file|
  run "rm #{file}"
end

##################################################################################
# Get some answers
mongo   = yes? 'Would you like to use MongoID?' unless database
haml    = yes? 'Would you like to use HAML?'
rspec   = yes? 'Would you like to use RSpec?'
minitest = yes? 'Would you like to use minitest instead?' unless rspec
heroku  = yes? 'Deploying to Heroku?'
unicorn = yes? 'Would you like to use Unicorn? (thin is the default)'
sorcery = yes? 'Would you like to use Sorcery?'
devise = yes? 'Would you like to use Devise instead?' unless sorcery
nine_sixty = yes? 'Would you like to use the 960 grid system?'

if database
  username = ask "Choose a database username: "
  password = ask "Choose a database password: (default is nothing) "
  run "cp config/database.yml config/database.yml.example"
  gsub_file "config/database.yml", /  username:\s\w+\n/, "  username: #{username}\n"
  gsub_file "config/database.yml", /  password:\s\w+\n/, "  password: #{password}\n"
  run "rake db:create && rake db:migrate"
end

##################################################################################
# type of view template
template = haml ? 'html.haml' : 'html.erb'

gsub_file 'config/application.rb', /:password/, ':password, :password_confirmation'

##################################################################################
# Create files and directories that I use
['app/views/application', 'app/assets/stylesheets/pages', 'app/assets/stylesheets/partials', 'db/seeds'].each do |dir|
  run "mkdir -p #{dir}"
end

['Readme.mkd', "app/views/application/_flash_messages#{template}", "app/assets/stylesheets/variables.sass", "app/#{appname}/.gitkeep"].each do |file|
  run "touch #{file}"
end

if rspec || minitest
  ["spec/#{appname}/.gitkeep"].each do |file|
    run "touch #{file}"
  end
end


##################################################################################
# Setup my sass style
create_file 'app/assets/stylesheets/application.sass', <<-SASS
@import compass/reset
@import base

// Pages
// @import pages/home
SASS

# gsub_file "app/assets/stylesheets/application.css", /require_tree \./, 'require grand_central'

# Setup a real gitignore file
run 'rm .gitignore'
file '.gitignore', <<-FILE
.DS_Store
*.sw*
log/*.log
config/database.yml
tmp/*
db/*.sqlite*
gems/*
!gems/cache
public/assets
public/system
public/uploads
coverage
.sass-cache
.bundle-cache
vendor/ruby
vendor/local
vendor/bundle
FILE


##################################################################################
# Setup Gems to install
if rspec
  gsub_file 'Gemfile', /group :test do\n  # Pretty printed test output\n  gem 'turn', :require => false\nend/, ''
end

test    = %w(factory_girl_rails database_cleaner capybara guard guard-spork guard-rails guard-rspec faker growl spork-rails)
default = %w()
dev     = %w(foreman letter_opener sextant thin)
testdev = %w(pry-rails)
assets = %w(sass-rails coffee-rails compass-rails uglifier)
production = %w()

unicorn ? production.push("unicorn") : production.push("thin")

default.push("haml-rails")                  if haml
default.push("bson_ext", "mongoid")                                   if mongo
default.push("heroku", "heroku-rails")                                if heroku
default.push("devise")  if devise
default.push("sorcery") if sorcery
test.push("rspec-rails")                                              if rspec
test.push('minitest', 'turn') if minitest
assets.push("compass-960-plugin") if nine_sixty

def gem_setup(gems, indent=true)
  tab = indent ? "\t" : ''
  gems.collect { |g| "#{tab}gem '#{g}'" }.join("\n")
end

append_to_file "Gemfile", <<-FILE

#{gem_setup(default, false)}

group :assets do
#{gem_setup(assets)}
end

group :production do
#{gem_setup(production)}
end

group :development do
#{gem_setup(dev)}
end

group :test do
#{gem_setup(test)}
end

group :test, :development do
#{gem_setup(testdev)}
end
FILE

##################################################################################
# Run Bundle install and Package the gems
run "bundle install --without=production --path vendor"
run "bundle package"


##################################################################################
# Setup Minitest
if minitest
  run "mkdir spec"
  create_file 'spec/spec_helper.rb', <<-FILE
ENV["RAILS_ENV"] = "test"
require File.expand_path("../../config/environment", __FILE__)
require 'minitest/autorun'
require 'capybara/rails'
require 'active_support/testing/setup_and_teardown'
require 'database_cleaner'

DatabaseCleaner.strategy = :truncation

class MiniTest::Spec
  include Factory::Syntax::Methods
  before(:each) { DatabaseCleaner.clean }
end

class IntegrationTest < MiniTest::Spec
  include Rails.application.routes.url_helpers
  include Capybara::DSL
  register_spec_type(/integration$/, self)
end

class HelperTest < MiniTest::Spec
  include ActiveSupport::Testing::SetupAndTeardown
  include ActionView::TestCase::Behavior
  register_spec_type(/Helper$/, self)
end

# Turn configuration (defaults to :pretty)
# Turn.config.format = :outline

  FILE

  # Create a rake task for it
  create_file 'lib/tasks/minitest.rake', <<-FILE
require 'rake/testtask'

Rake::TestTask.new(spec: 'db:test:prepare') do |t|
  t.libs    << 'spec'
  t.pattern = "spec/**/*_spec.rb"
end

task default: :spec
  FILE
end

##################################################################################
# Setup Devise Mailers
gsub_file 'config/environments/development.rb', /# Don't care if the mailer can't send/, '# Mailer Setup'
gsub_file 'config/environments/development.rb', /config.action_mailer.raise_delivery_errors = false/ do
<<-RUBY
config.action_mailer.default_url_options = { :host => 'localhost:3000' }
config.action_mailer.delivery_method = :letter_opener
RUBY
end

gsub_file 'config/environments/production.rb', /config.i18n.fallbacks = true/ do
<<-RUBY
config.i18n.fallbacks = true

  config.action_mailer.default_url_options = { :host => 'localhost:3000' }
  ### ActionMailer Config
  # Setup for production - deliveries, no errors raised
  config.action_mailer.delivery_method        = :sendmail
  config.action_mailer.perform_deliveries     = true
  config.action_mailer.raise_delivery_errors  = false
  config.action_mailer.default :charset => "utf-8"
RUBY
end

gsub_file 'config/environments/test.rb', /# Tell Action Mailer not to deliver emails to the real world\./, '# Devise Mailer Setup'
gsub_file 'config/environments/test.rb', /# Settings specified here will take precedence over those in config\/application.rb/ do
<<-RUBY
config.action_mailer.default_url_options = { :host => 'localhost:3000' }
RUBY
end

##################################################################################
# Rake db:reseed
if database
  file 'lib/tasks/reseed.rake', <<-FILE
namespace :db do
  desc "Reseed database"
  task :reseed => :environment do
    Rake::Task['db:remigrate'].invoke
    Rake::Task['db:seed'].invoke
  end
  namespace :test do
    task :prepare do
    end
  end

  desc 'Remigrate the database'
  task remigrate: :environment do
    Rake::Task['db:drop'].invoke
    Rake::Task['db:create'].invoke
    Rake::Task['db:migrate'].invoke
    Rake::Task['db:test:prepare'].invoke
  end
end
  FILE
end

##################################################################################
# Setting up the template generators
h = haml ? 'haml' : 'erb'
template_engine = "g.template_engine      :#{h}"

# Rspec for generators
if rspec
  testing_generator = "g.test_framework       :rspec, :fixture => false, :views => false"
  testing_views     = "g.view_specs   false"
  testing_fixtures  = "g.fixture_replacement  :factory_girl,  :dir => 'spec/factories'"
elsif minitest
  testing_generator = "g.test_framework       nil"
  testing_fixtures  = "g.fixture_replacement  :factory_girl,  :dir => 'spec/factories'"
else
  testing_generator = "g.test_framework       :test_unit, :fixture => false, :views => false"
  testing_fixtures  = "g.fixture_replacement  :factory_girl,  :dir => 'test/factories'"
end

# Mongoid
if mongo
  orm = "g.orm :mongoid"
end

initializer 'generators.rb', <<-RUBY
Rails.application.config.generators do |g|
  g.stylesheets          false
  #{orm}
  #{template_engine}
  #{testing_generator}
  #{testing_views}
  #{testing_fixtures}
end
RUBY

##################################################################################
# Run generators

if devise
  generate 'devise:install'
  generate 'devise:views'
end

if sorcery
  generate "sorcery:install remember_me reset_password activity_logging"
end

generate 'rspec:install' if rspec
generate 'heroku:config' if heroku

# MongoDB
if mongo
  generate 'mongoid:config'
  generate 'mongoid:install'
end


# ##################################################################################
# # Convert Devise Views from ERB to HAML
if haml and devise
  run "for i in `find app/views/devise -name '*.erb'` ; do bundle exec html2haml -e $i ${i%erb}haml ; rm $i ; done"
end

##################################################################################
# Rspec setup
format = "--format documentation\n-I app/#{appname}"
if rspec
  append_to_file '.rspec', format
  run "rm -rf test"
  run 'mkdir -p spec/requests'

  # Setup spec helper a bit (tired of doing this)
  gsub_file 'spec/spec_helper.rb', /config.use_transactional_fixtures = true/, ''
  gsub_file 'spec/spec_helper.rb', /config.fixture_path = "\#{::Rails.root}\/spec\/fixtures"/, ''
  gsub_file 'spec/spec_helper.rb', /\# instead of true./ do
  <<-CODE

 Spork.prefork do
  Dir[Rails.root.join("spec/support/**/*.rb")].each {|f| require f}
  # Capybara.javascript_driver = :webkit
  # FakeWeb.allow_net_connect = false

  RSpec.configure do |config|
    config.mock_with :rspec
    config.use_transactional_fixtures = false

    config.before(:suite) do
      DatabaseCleaner.strategy = :truncation
    end

    config.after(:each) do
      DatabaseCleaner.clean
    end

    config.before(:each) do
      DatabaseCleaner.start
      # reset_email
    end

    config.include FactoryGirl::Syntax::Methods
    # config.include(MailerMacros)

  end

end

Spork.each_run do
  FactoryGirl.reload
end

Spork.each_run do
  FactoryGirl.reload
end
  CODE
  end


end

##################################################################################
# Setup the foreman procfile and include the webserver

if unicorn
  # create unicorn's config file
  create_file 'config/unicorn.rb', <<-UNICORN
worker_processes 4 # amount of unicorn workers to spin up
timeout 30         # restarts workers that hang for 30 seconds
UNICORN

  procfile_contents = 'web: bundle exec unicorn -p $PORT -c config/unicorn.rb'

else # use thin
  procfile_contents = 'web: bundle exec thin start -p $PORT'
end

# create the proc file for thin
create_file 'Procfile', procfile_contents

##################################################################################
# Git setup
git :init
git :add => '.'
git :commit => "-am 'Initial commit of the project'"