require 'fileutils'
require 'tmpdir'

module Kafo
  class HieraConfigurer
    attr_reader :temp_dir, :config_path, :data_dir, :logger

    def initialize(user_config_path, modules, modules_order, hiera_custom_values)
      @user_config_path = user_config_path
      @modules = modules
      @modules_order = modules_order
      @hiera_custom_values = hiera_custom_values
      @logger = KafoConfigure.logger
    end

    def write_configs
      @temp_dir = Dir.mktmpdir('kafo_hiera')
      @config_path = File.join(temp_dir, 'hiera.conf')
      @data_dir = File.join(temp_dir, 'data')

      if @user_config_path
        logger.debug("Merging existing Hiera config file from #{@user_config_path}")
        user_config = YAML.load(File.read(@user_config_path))
        user_data_dir = user_config[:yaml][:datadir] if user_config[:yaml]
      else
        user_config = {}
        user_data_dir = false
      end
      logger.debug("Writing Hiera config file to #{config_path}")
      File.open(config_path, 'w') do |f|
        # merge required config changes into the user's Hiera config
        f.write(format_yaml_symbols(generate_config(user_config).to_yaml))
      end

      if user_data_dir
        logger.debug("Copying Hiera data files from #{user_data_dir} to #{data_dir}")
        FileUtils.cp_r(user_data_dir, data_dir)
      else
        logger.debug("Creating Hiera data files in #{data_dir}")
        FileUtils.mkdir(data_dir)
      end

      File.open(File.join(data_dir, 'kafo_custom.yaml'), 'w') do |f|
        f.write(format_yaml_symbols(@custom_hiera_vales.to_yaml))
      end

      File.open(File.join(data_dir, 'kafo_answers.yaml'), 'w') do |f|
        f.write(format_yaml_symbols(generate_data(@modules).to_yaml))
      end
    end

    def generate_config(config = {})
      config ||= {}

      # ensure YAML is enabled
      config[:backends] ||= []
      config[:backends] << 'yaml' unless config[:backends].include?('yaml')

      # ensure kafo_answers is present and most specific
      config[:hierarchy] ||= []
      config[:hierarchy].unshift('kafo_answers') unless config[:hierarchy].include?('kafo_answers')

      # ensure kafo_custom is present and just before kafo_answers
      unless config[:hierarchy].include?('kafo_custom')
        config[:hierarchy].insert(config[:hierarchy].find_index('kafo_answers'), 'kafo_custom')
      end

      # use our copy of the data dir
      config[:yaml] ||= {}
      config[:yaml][:datadir] = data_dir

      config
    end

    def generate_data(modules)
      classes = []
      data = modules.select(&:enabled?).inject({}) do |config, mod|
        classes << mod.class_name
        config.update(Hash[mod.params_hash.map { |k, v| ["#{mod.class_name}::#{k}", v] }])
      end
      data['classes'] = @modules_order ? sort_modules(classes, @modules_order) : classes
      data
    end

    def sort_modules(modules, order)
      (order & modules) + (modules - order)
    end

    def format_yaml_symbols(data)
      data.gsub('!ruby/sym ', ':')
    end
  end
end
