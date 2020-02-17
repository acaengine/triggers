module ACAEngine::Triggers
  APP_NAME    = "engine-triggers"
  API_VERSION = "v1"
  VERSION     = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
end
