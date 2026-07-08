require 'json'
require 'rgeo/geo_json'
require 'rgeo/svg' # integrated lib for now
require 'active_support/core_ext/module/delegation'
require 'victor' # for SVG

module Charta
  # Represents a Geometry with SRID
  class Geometry
    def initialize(feature, properties = {})
      self.feature = feature
      @properties = properties
    end

    def inspect
      "<#{self.class.name}(#{to_ewkt})>"
    end

    # Returns the type of the geometry as a string. Example: point,
    # multi_polygon, geometry_collection...
    def type
      Charta.underscore(feature.geometry_type.type_name).to_sym
    end

    # Returns the type of the geometry as a string. EG: 'ST_Linestring', 'ST_Polygon',
    # 'ST_MultiPolygon' etc. This function differs from GeometryType(geometry)
    # in the case of the string and ST in front that is returned, as well as the fact
    # that it will not indicate whether the geometry is measured.
    def collection?
      feature.geometry_type == RGeo::Feature::GeometryCollection
    end

    # Return the spatial reference identifier for the ST_Geometry
    def srid
      feature.srid.to_i
    end

    # Returns the Well-Known Text (WKT) representation of the geometry/geography
    # without SRID metadata
    def to_text
      feature.as_text.match(/\ASRID=.*;(.*)/)[1]
    end

    alias as_text to_text
    alias to_wkt to_text

    # Returns EWKT: WKT with its SRID
    def to_ewkt
      Charta.generate_ewkt(feature).to_s
    end

    alias to_s to_ewkt

    def ewkt
      puts 'DEPRECATION WARNING: Charta::Geometry.ewkt is deprecated. Please use Charta::Geometry.to_ewkt instead'
      to_ewkt
    end

    #  Return the Well-Known Binary (WKB) representation of the geometry with SRID meta data.
    def to_binary
      generator = RGeo::WKRep::WKBGenerator.new(tag_format: :ewkbt, emit_ewkbt_srid: true)
      generator.generate(feature)
    end

    alias to_ewkb to_binary

    # Generate SVG from geometry
    # @param [Hash] options , the options for SVG object.
    # @option options [Hash] :mode could be :stroke or :fill
    # @option options [Hash] :color could be "orange", "red", "blue" or HTML color "#14TF15"
    # @option options [Hash] :fill_opacity could be '0' to '100'
    # @option options [Hash] :stroke_linecap could be 'round', 'square', 'butt'
    # @option options [Hash] :stroke_linejoin default 'round'
    # @option options [Hash] :stroke_width default '5%'
    # @note more informations on https://developer.mozilla.org/fr/docs/Web/SVG/Tutorial/Fills_and_Strokes
    # @return [String] the SVG image
    def to_svg(options = {})
      # set default options if not present
      options[:mode] ||= :stroke
      options[:color] ||= 'black'
      options[:fill_opacity] ||= '100' # 0 to 100
      options[:stroke_linecap] ||= 'butt' # round, square, butt
      options[:stroke_linejoin] ||= 'round' #
      options[:stroke_width] ||= '5%'

      svg = Victor::SVG.new template: :html
      svg.setup width: 180, height: 180, viewBox: bounding_box.svg_view_box.join(' ')
      # return a stroke SVG with options
      if options[:mode] == :stroke
        svg.path d: to_svg_path, fill: 'none', stroke: options[:color], stroke_linecap: options[:stroke_linecap],
stroke_linejoin: options[:stroke_linejoin], stroke_width: options[:stroke_width]
      # return a fill SVG with options
      elsif options[:mode] == :fill
        svg.path d: to_svg_path, fill: options[:color], fill_opacity: options[:fill_opacity]
      end
      svg.render
    end

    # Return the geometry as Scalar Vector Graphics (SVG) path data.
    def to_svg_path
      RGeo::SVG.encode(feature)
    end

    # Return the geometry as a Geometry Javascript Object Notation (GeoJSON) element.
    def to_geojson
      to_json_object.to_json
    end

    alias to_json to_geojson

    # Returns object in JSON (Hash)
    def to_json_object
      RGeo::GeoJSON.encode(feature)
    end

    # Test if the other measure is equal to self
    def ==(other)
      other_geometry = Charta.new_geometry(other).transform(srid)
      return true if empty? && other_geometry.empty?
      return inspect == other_geometry.inspect if collection? && other_geometry.collection?

      feature.equals?(other_geometry.feature)
    end

    # Test if the other measure is equal to self
    def !=(other)
      other_geometry = Charta.new_geometry(other).transform(srid)
      return true if empty? && other_geometry.empty?
      return inspect == other_geometry.inspect if collection? && other_geometry.collection?

      !feature.equals?(other_geometry.feature)
    end

    # Returns true if Geometry is a Surface
    def surface?
      if collection?
        feature.any? { |geometry| Charta.new_geometry(geometry).surface? }
      else
        [RGeo::Feature::Polygon, RGeo::Feature::MultiPolygon].include? feature.geometry_type
      end
    end

    # Returns area in unit corresponding to the SRS
    def area
      if surface?
        if collection?
          feature.sum { |geometry| Charta.new_geometry(geometry).area }
        else
          feature.area
        end
      else
        0
      end
    end

    # Returns true if this Geometry is an empty geometrycollection, polygon,
    # point etc.
    def empty?
      feature.empty?
    end

    alias blank? empty?

    # Computes the geometric center of a geometry, or equivalently, the center
    # of mass of the geometry as a POINT.
    def centroid
      return nil unless surface? && !feature.empty?

      point = feature.centroid
      [point.y, point.x]
    end

    # Returns a POINT guaranteed to lie on the surface.
    def point_on_surface
      return nil unless surface?

      point = feature.point_on_surface
      [point.y, point.x]
    end

    def convert_to(new_type)
      case new_type
      when type
        self
      when :multi_point
        flatten_multi(:point)
      when :multi_line_string
        flatten_multi(:line_string)
      when :multi_polygon
        flatten_multi(:polygon)
      else
        self
      end
    end

    def flatten_multi(as_type)
      items = []
      as_multi_type = "multi_#{as_type}".to_sym
      if type == as_type
        items << feature
      elsif type == :geometry_collection
        feature.each do |geom|
          type_name = Charta.underscore(geom.geometry_type.type_name).to_sym
          if type_name == as_type
            items << geom
          elsif type_name == as_multi_type
            geom.each do |item|
              items << item
            end
          end
        end
      end
      Charta.new_geometry(feature.factory.send(as_multi_type, items))
    end

    # Returns a new geometry with the coordinates converted into the new SRS
    def transform(new_srid)
      return self if new_srid == srid
      raise 'Proj is not supported. Cannot tranform' unless RGeo::CoordSys::Proj4.supported?

      new_srid = Charta::SRS[new_srid] || new_srid
      database = self.class.srs_database
      new_proj_entry = database.get(new_srid)
      raise "Cannot find proj for SRID: #{new_srid}" if new_proj_entry.nil?

      new_feature = RGeo::CoordSys::Proj4.transform(
        database.get(srid).proj4,
        feature,
        new_proj_entry.proj4,
        self.class.factory(new_srid)
      )
      generator = RGeo::WKRep::WKTGenerator.new(tag_format: :ewkt, emit_ewkt_srid: true)
      Charta.new_geometry(generator.generate(new_feature))
    end

    # Produces buffer
    def buffer(radius)
      feature.buffer(radius)
    end

    def merge(other)
      other_geometry = Charta.new_geometry(other).transform(srid)
      feature.union(other_geometry.feature)
    end

    alias + merge

    def intersection(other)
      other_geometry = Charta.new_geometry(other).transform(srid)
      feature.intersection(other_geometry.feature)
    end

    def intersects?(other)
      other_geometry = Charta.new_geometry(other).transform(srid)
      feature.intersects?(other_geometry.feature)
    end

    def difference(other)
      other_geometry = Charta.new_geometry(other).transform(srid)
      feature.difference(other_geometry.feature)
    end

    alias - difference

    def bounding_box
      unless defined? @bounding_box
        bbox = RGeo::Cartesian::BoundingBox.create_from_geometry(feature)
        instance_variable_set('@x_min', bbox.min_x || 0)
        instance_variable_set('@y_min', bbox.min_y || 0)
        instance_variable_set('@x_max', bbox.max_x || 0)
        instance_variable_set('@y_max', bbox.max_y || 0)
        @bounding_box = BoundingBox.new(@y_min, @x_min, @y_max, @x_max)
      end
      @bounding_box
    end

    %i[x_min y_min x_max y_max].each do |name|
      define_method name do
        bounding_box.send(name)
      end
    end

    def find_srid(name_or_srid)
      Charta.find_srid(name_or_srid)
    end

    # Returns the underlaying object managed by Charta: the RGeo feature
    def feature
      unless defined? @feature
        if defined? @ewkt
          @feature = ::Charta::Geometry.from_ewkt(@ewkt)
          @properties = @options.dup if @options
        else
          raise StandardError.new('Invalid geometry (no feature, no EWKT)')
        end
      end
      @feature.dup
    end

    alias to_rgeo feature

    def feature=(new_feature)
      raise ArgumentError.new("Feature can't be nil") if new_feature.nil?

      @feature = new_feature
    end

    def to_json_feature(properties = {})
      { type: 'Feature', properties: properties, geometry: to_json_object }
    end

    def method_missing(name, *args, &block)
      target = to_rgeo
      if target.respond_to? name
        target.send name, *args
      else
        raise StandardError.new("Method #{name} does not exist for #{self.class.name}")
      end
    end

    def respond_to_missing?(name, include_private = false)
      return false if name == :init_with

      super
    end

    class << self
      def srs_database
        @srs_database ||= RGeo::CoordSys::SRSDatabase::Proj4Data.new('epsg', authority: 'EPSG', cache: true)
      end

      def factory(srid = 4326, uses_lenient_assertions = true)
        if srid.to_i == 4326
          factory = projected_factory(srid)
          factory.set_property(:uses_lenient_assertions, true) if uses_lenient_assertions && factory.respond_to?(:set_property)
        else
          factory = geos_factory(srid)
        end

        factory
      end

      def feature(ewkt_or_rgeo)
        return from_rgeo(ewkt_or_rgeo) if ewkt_or_rgeo.is_a? RGeo::Feature::Instance

        from_ewkt(ewkt_or_rgeo)
      end

      def from_rgeo(rgeo)
        srid = rgeo.srid
        RGeo::Feature.cast(rgeo, factory: Geometry.factory(srid))
      end

      def from_ewkt(ewkt)
        # Cleans empty geometries
        ewkt = ewkt.gsub(/(GEOMETRYCOLLECTION|GEOMETRY|((MULTI)?(POINT|LINESTRING|POLYGON)))\(\)/, '\1 EMPTY')
        srs = ewkt.split(/[\=\;]+/)[0..1]
        srid = nil
        srid = srs[1] if srs[0] =~ /srid/i
        srid ||= 4326
        factory(srid).parse_wkt(ewkt)
      rescue RGeo::Error::ParseError => e
        raise "Invalid EWKT (#{e.class.name}: #{e.message}): #{ewkt}"
      end

      private

        def geos_factory(srid)
          RGeo::Geos.factory(
            srid: srid,
            wkt_generator: {
              type_format: :ewkt,
              emit_ewkt_srid: true,
              convert_case: :upper
            },
            wkt_parser: {
              support_ewkt: true
            },
            wkb_generator: {
              type_format: :ewkb,
              emit_ewkb_srid: true,
              hex_format: true
            },
            wkb_parser: {
              support_ewkb: true
            }
          )
        end

        def projected_factory(srid)
          # Palier 5: +type=crs is required for rgeo-proj4 3.x's #get_geographic
          # (used internally by RGeo::Geographic.projected_factory to derive the
          # WGS84 companion CRS). Without it, PROJ 6+'s proj_crs_get_geodetic_crs
          # rejects the raw definition ("Object is not a CRS") since it isn't
          # explicitly typed as a full CRS -- 2.0.1's legacy proj_api.h-based
          # implementation didn't make this distinction.
          proj4 = '+proj=cea +lon_0=0 +lat_ts=30 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs +type=crs'
          RGeo::Geographic.projected_factory(
            srid: srid,
            wkt_generator: {
              type_format: :ewkt,
              emit_ewkt_srid: true,
              convert_case: :upper
            },
            wkt_parser: {
              support_ewkt: true
            },
            wkb_generator: {
              type_format: :ewkb,
              emit_ewkb_srid: true,
              hex_format: true
            },
            wkb_parser: {
              support_ewkb: true
            },
            projection_srid: 6933,
            projection_proj4: proj4
          )
        end
    end
  end
end
