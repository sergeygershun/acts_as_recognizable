module ActsAsRecognizable

  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods

    def acts_as_recognizable(options = {}, &block)
      @@default_options = {
        :slug_field_name => :slug, 
        :sluggable_field_name => :title
      }

      class << self
        attr_reader :slug_field_name, :sluggable_field_name
        
        def find_with_slug(*args)
          args.unshift(args.shift.split("-").last) if args.first.is_a?(String) && args.first !~ /^\d+$/
          find_without_slug(*args)
        end
        alias_method_chain :find, :slug        
      end

      include InstanceMethods

      @options = @@default_options.merge options

      @slug_field_name = @options[:slug_field_name]
      @sluggable_field_name = @options[:sluggable_field_name]
      
      before_validation_on_create(block_given? ? block.to_proc : :make_slug_without_id)      
      validates_uniqueness_of @slug_field_name.to_sym unless @options[:append_id]

      after_save :slug_saved

      class_eval <<-CODE, __FILE__, __LINE__
        def #{@slug_field_name}
          @old_slug_version || read_attribute("#{@slug_field_name}")
        end
      
        def #{@slug_field_name}=(value)
          @old_slug_version = #{@slug_field_name} unless #{@slug_field_name}.blank?
          write_attribute("#{@slug_field_name}", value)
        end
        
        def #{@sluggable_field_name}=(value)
          write_attribute("#{@sluggable_field_name}", value.to_s.gsub(/\s+/, ' ').strip)
        end
        
        private
        def slug_saved
          @old_slug_version = nil          
          if (#{!!@options[:append_id]})
            self.#{@slug_field_name} = self.class.slugalize("\#{self.make_slug_without_id}-\#{self.id}")
          else
            make_slug_without_id
          end
          self.send :update_without_callbacks      
          @old_slug_version = nil
        end
      CODE
    end

    def slug_cache
      @slug_cache ||= find(:all).inject(HashWithIndifferentAccess.new) do |cache, model| 
        cache[model.id.to_s] = model.slug;
        cache[model.slug] = model.id; 
        cache
      end
    end
    
    def clear_slug_cache
      @slug_cache = nil
    end

    def id_by_slug(slug)
      slug_cache[slug]
    end
    
    def slug_by_id(id)
      slug_cache[id.to_s]
    end

    def slugalize(str)
      URI.escape(str.to_s.gsub(/[-'"&*\(\)!@#\$.,\/\s_]+/, '-').downcase).gsub(/^-/, '').gsub(/-$/, '')
    end

  end
  
  module InstanceMethods
    
    def slug_field
      send(self.class.slug_field_name.to_sym)
    end

    def slug_field=(value)
      send("#{self.class.slug_field_name}=".to_sym, value)
    end

    def sluggable_field
      send(self.class.sluggable_field_name.to_sym)
    end

    def to_param
      slug_field unless slug_field.blank?
    end
    
    def make_slug_without_id
      self.slug_field = self.class.slugalize(sluggable_field) unless sluggable_field.blank?
    end                
    
  end
end
