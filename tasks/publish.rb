#!/opt/puppetlabs/puppet/bin/ruby
# Copyright 2017 Google Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Publish a message to a specific topic.
#
# Command line arguments: JSON object from STDIN with the following fields:
#
# - topic: The name of the topic to send the message to.
# - attributes: Optional attributes in { name => val } format (default: {})
# - message: The message to be published.
# - project: the project name where the cluster is hosted
# - credential: Path to a service account credentials file

PUBSUB_ADM_SCOPES = [
  'https://www.googleapis.com/auth/pubsub'
].freeze

require 'puppet'

# We want to re-use code already written for the GCP modules
Puppet.initialize_settings

# Puppet apply does special stuff to load library code stored in modules
# but that magic is available in Bolt so we emulate it here.  We look in
# the local user's .puppetlabs directory or if running at "root" we look
# in the directory where Puppet pluginsyncs to.
libdir = if Puppet.run_mode.user?
           Dir["#{Puppet.settings[:codedir]}/modules/*/lib"]
         else
           File.path("#{Puppet.settings[:vardir]}/lib").to_a
         end
libdir << File.expand_path("#{File.dirname(__FILE__)}/../lib")
libdir.each { |l| $LOAD_PATH.unshift(l) unless $LOAD_PATH.include?(l) }

require 'base64'
require 'google/auth/gauth_credential'
require 'google/pubsub/api/gpubsub_topic'
require 'google/pubsub/network/post'

# Validates user input
def validate(params, arg_id, default = nil)
  arg = arg_id.id2name
  raise "Missing parameter '#{arg}' from stdin" \
    if default.nil? && !params.key?(arg)
  params.key?(arg) ? params[arg] : default
end

# Parses and validates user input
params = {}
begin
  Timeout.timeout(3) do
    params = JSON.parse(STDIN.read)
  end
rescue Timeout::Error
  puts({ status: 'failure', error: 'Cannot read JSON from stdin' }.to_json)
  exit 1
end

topic = validate(params, :topic)
attributes = validate(params, :attributes, {})
message = validate(params, :message)
project = validate(params, :project)
credential = validate(params, :credential)

cred = Google::Auth::GAuthCredential \
       .serviceaccount_for_function(credential, PUBSUB_ADM_SCOPES)
pubsub_message = Google::Pubsub::Api::Topic \
                 .new(topic, project, cred)

begin
  resp = pubsub_message.publish(message, attributes)
  puts({ status: 'success', id: resp['messageIds'][0] }.to_json)
  exit 0
rescue Puppet::Error => e
  puts({ status: 'failure', error: e }.to_json)
  exit 1
end
