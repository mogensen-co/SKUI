module SKUI

  require File.join( PATH, 'base.rb' )
  require File.join( PATH, 'bridge.rb' )
  require File.join( PATH, 'control_manager.rb' )
  require File.join( PATH, 'debug.rb' )


  # Basic window class. Use this as the foundation for custom window types.
  #
  # @since 1.0.0
  class Window < Base

    include ControlManager

    # @since 1.0.0
    define_event( :ready )

    # @since 1.0.0
    THEME_DEFAULT = 'theme_os.css'.freeze

    # @private
    attr_reader( :bridge )

    # @param [Hash] options
    #
    # @since 1.0.0
    def initialize( options = {} )
      super()

      defaults = {
        :title            => 'Untitled',

        :left             => 400,
        :top              => 250,
        :width            => 300,
        :height           => 200,

        :width_limit      => nil,
        :height_limit     => nil,

        :resizable        => false,
        :minimize         => false,
        :maximize         => false,

        :modal            => false,

        :preferences_key  => nil,

        :theme            => THEME_DEFAULT
      }
      active_options = defaults.merge( options )

      @window = self
      @options = active_options

      # Create a dummy WebDialog here in order for the Bridge to respond in a
      # more sensible manner other than being `nil`. The WebDialog is recreated
      # right before the window is displayed due to a SketchUp bug.
      # @see #show
      @webdialog = UI::WebDialog.new
      @bridge = Bridge.new( self, @webdialog )
    end

    # Returns an array with the width and height of the client area.
    #
    # @return [Array(Integer,Integer)]
    # @since 1.0.0
    def client_size
      @bridge.call( 'Webdialog.get_client_size' )
    end

    # Adjusts the window so the client area fits the given +width+ and +height+.
    #
    # @param [Array(Integer,Integer)] value
    #
    # @return [Boolean] Returns false if the size can't be set.
    # @since 2.5.0
    def client_size=( value )
      width, height = value
      unless @webdialog.visible?
        # (?) Queue up size for when dialog opens.
        return false
      end
      # (!) Cache size difference.
      @webdialog.set_size( width, height )
      client_width, client_height = get_client_size()
      adjust_width  = width  - client_width
      adjust_height = height - client_height
      unless adjust_width == 0 && adjust_height == 0
        new_width  = width  + adjust_width
        new_height = height + adjust_height
        @webdialog.set_size( new_width, new_height )
      end
      true
    end

    # @return [Nil]
    # @since 1.0.0
    def bring_to_front
      @webdialog.bring_to_front
    end

    # @return [Nil]
    # @since 1.0.0
    def close
      @webdialog.close
    end

    # @overload set_position( left, top )
    #   @param [Numeric] left
    #   @param [Numeric] top
    #
    # @return [Nil]
    # @since 1.0.0
    def set_position( *args )
      @webdialog.set_position( *args )
    end

    # @overload set_size( width, height )
    #   @param [Numeric] width
    #   @param [Numeric] height
    #
    # @return [Nil]
    # @since 1.0.0
    def set_size( *args )
      @webdialog.set_size( *args )
    end

    # @since 1.0.0
    def show
      if @webdialog.visible?
        @webdialog.bring_to_front
      else
        # Recreate WebDialog instance in order for last position and size to be
        # used. Otherwise old preferences would be used.
        @webdialog = init_webdialog( @options )
        @bridge = Bridge.new( self, @webdialog )
        # OSX doesn't have modal WebDialogs. Instead a 'modal' WebDialog means
        # it'll stay on top of the SketchUp window - where as otherwist it'd
        # fall behind.
        if PLATFORM_IS_OSX
          # (!) Implement alternative for OSX modal windows.
          @webdialog.show_modal
        else
          if @options[:modal]
            @webdialog.show_modal
          else
            @webdialog.show
          end
        end
      end
    end

    # @return [String]
    # @since 1.0.0
    def title
      @options[:title].dup
    end

    # @return [String]
    # @since 1.0.0
    def to_js
      'Window'.inspect
    end

    # @return [Boolean]
    # @since 1.0.0
    def visible?
      @webdialog.visible?
    end

    # @overload write_image( image_path, top_left_x, top_left_y,
    #                        bottom_right_x, bottom_right_y )
    #   @param [String] image_path
    #   @param [Numeric] top_left_x
    #   @param [Numeric] top_left_y
    #   @param [Numeric] bottom_right_x
    #   @param [Numeric] bottom_right_y
    #
    # @return [Nil]
    # @since 1.0.0
    def write_image( *args )
      @webdialog.write_image( *args )
    end

    private

    # @param [UI::WebDialog] webdialog
    # @param [String] callback_name
    # @param [Symbol] method_id
    #
    # @return [Nil]
    # @since 1.0.0
    def add_callback( webdialog, callback_name, method_id )
      proc = method( method_id ).to_proc
      webdialog.add_action_callback( callback_name, &proc )
      nil
    end

    # Called when the HTML DOM is ready.
    #
    # @param [UI::WebDialog] webdialog
    # @param [String] params
    #
    # @return [Nil]
    # @since 1.0.0
    def event_window_ready( webdialog, params )
      Debug.puts( '>> Dialog Ready' )
      bridge.add_container( self )
      # (!) Inject theme CSS.
      trigger_event( :ready )
      nil
    end
    
    # Called when a control triggers an event.
    # params possibilities:
    #   "<ui_id>||<event>"
    #   "<ui_id>||<event>||arg1,arg2,arg3"
    #
    # @param [UI::WebDialog] webdialog
    # @param [String] params
    #
    # @return [Nil]
    # @since 1.0.0
    def event_callback( webdialog, params )
      #Debug.puts( '>> Event Callback' )
      #Debug.puts( params )
      ui_id, event_str, args_str = params.split('||')
      event = event_str.intern
      # Catch Debug Console callbacks
      return Debug.puts( args_str ) if ui_id == 'Console'
      # Process Control
      control = find_control_by_ui_id( ui_id )
      if control
        if args_str
          args = args_str.split(',')
          control.trigger_event( event, *args )
        else
          control.trigger_event( event )
        end
      end
    ensure
      # Inform the Webdialog the message was received so it can process any
      # remaining messages.
      bridge.call( 'Bridge.pump_message' )
      nil
    end

    # Called when a URL link is clicked.
    #
    # @param [UI::WebDialog] webdialog
    # @param [String] params
    #
    # @return [Nil]
    # @since 1.0.0
    def event_open_url( webdialog, params )
      Debug.puts( '>> Open URL' )
      UI.openURL( params )
      nil
    end

    # @○param [Hash] options Same as #initialize
    #
    # @return [UI::WebDialog]
    # @since 1.0.0
    def init_webdialog( options )
      # Convert options to Webdialog arguments.
      wd_options = {
        :dialog_title     => options[:title],
        :preferences_key  => options[:preferences_key],
        :resizable        => options[:resizable],
        :scrollable       => false,
        :left             => options[:left],
        :top              => options[:top],
        :width            => options[:width],
        :height           => options[:height]
      }
      webdialog = UI::WebDialog.new( wd_options )
      # (?) Not sure if it's needed, but setting this to true for the time being.
      if webdialog.respond_to?( :set_full_security= )
        webdialog.set_full_security = true
      end
      # Hide the navigation buttons that appear on OSX.
      if webdialog.respond_to?( :navigation_buttons_enabled= )
        webdialog.navigation_buttons_enabled = true
      end
      # Ensure the size for fixed windows is set - otherwise SketchUp will use
      # the last saved properties.
      unless options[:resizable]
        webdialog.set_size( options[:width], options[:height] )
      end
      # Limit the size of the window. The limits can be either an Integer for
      # the maximum size of the window or a Range element which defines both
      # minimum and maximum size. If `range.max` return `nil` then there is no
      # maximum size.
      if options[:width_limit]
        if options[:width_limit].is_a?( Range )
          minimum = [ 0, options[:width_limit].min ].max
          maximum = options[:width_limit].max
          webdialog.min_width = minimum
          webdialog.max_width = maximum if maximum
        else
          webdialog.max_width = options[:width_limit]
        end
      end
      if options[:height_limit]
        if options[:height_limit].is_a?( Range )
          minimum = [ 0, options[:height_limit].min ].max
          maximum = options[:height_limit].max
          webdialog.min_width = minimum
          webdialog.max_width = maximum if maximum
        else
          webdialog.max_width = options[:height_limit]
        end
      end
      # (i) If procs are created in the initalize method for #add_action_callback
      #     then the WebDialog instance will not GC.
      add_callback( webdialog, 'SKUI_Window_Ready',   :event_window_ready )
      add_callback( webdialog, 'SKUI_Event_Callback', :event_callback )
      add_callback( webdialog, 'SKUI_Open_URL',       :event_open_url )
      # (i) There appear to be differences between OS when the HTML content
      #     is prepared. OSX loads HTML on #set_file? Inspect this.
      html_file = File.join( PATH_HTML, 'window.html' )
      webdialog.set_file( html_file )
      webdialog
    end

  end # class
end # module