module Sinatra
  module AssetPack
    # A package.
    #
    # == Common usage
    #
    #     package = assets.packages['application.css']
    #
    #     package.files   # List of local files
    #     package.paths   # List of URI paths
    #
    #     package.type    # :css or :js
    #     package.css?
    #     package.js?
    #
    #     package.path    # '/css/application.css' => where to serve the compressed file
    #
    #     package.to_development_html
    #     package.to_production_html
    #
    class Package
      include HtmlHelpers
      include BusterHelpers

      def initialize(assets, name, type, path, filespecs)
        @assets      = assets     # Options instance
        @name        = name       # "application"
        @type        = type       # :js or :css
        @path        = path       # '/js/app.js' -- where to served the compressed file
        @filespecs   = filespecs  # [ '/js/*.js' ]
      end

      attr_reader :type
      attr_reader :path
      attr_reader :filespecs
      attr_reader :name

      # Returns a list of URIs
      def paths_and_files
        list = @assets.glob(@filespecs)
        list.reject! { |path, file| @assets.ignored?(path) }
        list
      end

      def files
        paths_and_files.values.compact
      end

      def paths
        paths_and_files.keys
      end

      def mtime
        BusterHelpers.mtime_for(files)
      end

      # Returns the regex for the route, including cache buster.
      def route_regex
        re = @path.gsub(/(.[^.]+)$/) { |ext| "(?:\.[a-f0-9]{32})?#{ext}" }
        /^#{re}$/
      end

      def to_development_html(path_prefix, options={})
        paths_and_files.map { |path, file|
          path = add_cache_buster(path, file)
          path = add_path_prefix(path, path_prefix)
          link_tag(path, options)
        }.join("\n")
      end

      # The URI path of the minified file (with cache buster, but not a path prefix)
      def production_path
        add_cache_buster @path, *files
      end

      def to_production_html(path_prefix, options={})
        path = production_path
        path = add_path_prefix(path, path_prefix)
        link_tag path, options
      end

      def add_path_prefix(path, path_prefix)
        if path_prefix == '/'
          path
        else
          "#{path_prefix}#{path}"
        end
      end

      def minify(request)
        engine  = @assets.send(:"#{@type}_compression")
        options = @assets.send(:"#{@type}_compression_options")

        Compressor.compress combined(request), @type, engine, options
      end

      # The cache hash.
      def hash
        if @assets.app.development?
          "#{name}.#{type}/#{mtime}"
        else
          "#{name}.#{type}"
        end
      end

      def combined(request)
        headers = {}
        paths.map { |path|
          fetch_path(path, request)
        }.join("\n")
      end

      def js?()  @type == :js; end
      def css?() @type == :css; end

    private
      def link_tag(file, options={})
        file_path = HtmlHelpers.get_file_uri(file, @assets)

        if js?
          "<script src='#{e(file_path)}'#{kv(options)}></script>"
        elsif css?
          "<link rel='stylesheet' href='#{e(file_path)}'#{kv(options)} />"
        end
      end

      def fetch_path(path, request)
        @path_cache = {} unless defined?(@path_cache)
        return @path_cache[path] if @path_cache.has_key? path

        base_path = @assets.app.settings.wiki_options[:base_path]
        url = "#{$HOST_NAME}#{base_path}#{path}"

        url = URI.parse(url)
        http = Net::HTTP.new(url.host, url.port)
        request = Net::HTTP::Get.new(url.to_s)

        if request["HTTP_AUTHORIZATION"]
          headers = {
            "Authorization" => request["HTTP_AUTHORIZATION"]
          }
          request.initialize_http_header headers
        end

        result = http.request(request)

        if result.code == "200"
          if result.body.respond_to?(:force_encoding)
            response_encoding = 'UTF-8'
            encoding_bits = result.content_type.split(/;\s*charset\s*=\s*/)
            response_encoding = encoding_bits.last.upcase if encoding_bits.length > 1
            @path_cache[path] = result.body.force_encoding(response_encoding).encode(Encoding.default_external || 'ASCII-8BIT')
          else
            @path_cache[path] = result.body
          end
        else
          @path_cache[path] = ""
        end

        @path_cache[path]
      rescue StandardError => e
        puts e.inspect
        ""
      end
    end
  end
end
