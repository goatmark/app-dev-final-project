# config/initializers/execjs.rb

require 'execjs'

# Explicitly set ExecJS to use Node.js
ExecJS.runtime = ExecJS::Runtimes::Node
