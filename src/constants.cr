module ACAEngine::Triggers
  APP_NAME    = "engine-triggers"
  API_VERSION = "v1"
  VERSION     = {{ system("shards version").stringify.strip.downcase }}
end
