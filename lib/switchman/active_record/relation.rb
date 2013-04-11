module Switchman
  module ActiveRecord
    module Relation
      def self.included(klass)
        klass::SINGLE_VALUE_METHODS.concat [ :shard, :shard_source ]
        %w{initialize exec_queries update_all delete_all}.each do |method|
          klass.alias_method_chain(method, :sharding)
        end
      end

      def initialize_with_sharding(klass, table)
        initialize_without_sharding(klass, table)
        self.shard_value = Shard.current(klass.shard_category)
        self.shard_source_value = :implicit
      end

      def exec_queries_with_sharding
        return @records if loaded?
        case shard_value
        when DefaultShard, Shard.current(klass.shard_category)
          exec_queries_without_sharding
        when Shard
          shard_value.activate(klass.shard_category) { exec_queries_without_sharding }
        when Array, ::ActiveRecord::Relation, ::ActiveRecord::Base
          # TODO: implement local limit to avoid querying extra shards
          shards = shard_value
          shards = shard_value.associated_shards if shard_value.is_a?(::ActiveRecord::Base)
          @records = Shard.with_each_shard(shards, [klass.shard_category]) do
            shard(Shard.current(klass.shard_category), :to_a).send(:exec_queries_without_sharding)
          end
          @loaded = true
          @records
        end
      end

      %w{update_all delete_all}.each do |method|
        class_eval <<-RUBY
          def #{method}_with_sharding(*args)
            case shard_value
            when DefaultShard, Shard.current(klass.shard_category)
              #{method}_without_sharding(*args)
            when Shard
              shard_value.activate(klass.shard_category) { #{method}_without_sharding(*args) }
            when Array, ::ActiveRecord::Relation, ::ActiveRecord::Base
              shards = shard_value
              shards = shard_value.associated_shards if shard_value.is_a?(::ActiveRecord::Base)
              Shard.with_each_shard(shards, [klass.shard_category]) do
                shard(Shard.current(klass.shard_category), :to_a).#{method}_without_sharding(*args)
              end
            end
          end
        RUBY
      end
    end
  end
end