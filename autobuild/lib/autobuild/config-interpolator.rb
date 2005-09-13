class Regexp
    def each_match(string)
        string = string.to_str
        while data = match(string)
            yield(data)
            string = data.post_match
        end
    end
end

class UndefinedVariable < Exception
    attr_reader :name
    def initialize(name); @name = name end
end

class Interpolator
    VarDefKey = 'defines'
    MatchExpr = '\$\{([^}]+)\}|\$(\w+)'
    PartialMatch = Regexp.new(MatchExpr)
    WholeMatch = Regexp.new("^(?:#{MatchExpr})$")

    def self.interpolate(config, parent = nil)
        Interpolator.new(config, parent).interpolate
    end

    def initialize(node, parent = nil, variables = {})
        @node = node
        @variables = {}
        @defines = {}
        @parent = parent
    end

    def interpolate
        case @node
        when Hash
            @defines = (@node[VarDefKey] || {})

            interpolated = Hash.new
            @node.each do |k, v|
                next if k == VarDefKey
                interpolated[k] = Interpolator.interpolate(v, self)
            end

            interpolated

        when Array
            @node.collect { |v| Interpolator.interpolate(v, self) }

        else
            each_interpolation(@node) { |varname| value_of(varname) }
        end
    end

    def value_of(name)
        if @defines.has_key?(name)
            value = @defines.delete(name)
            @variables[name] = each_interpolation(value) { |varname|
                begin
                    value_of(varname)
                rescue UndefinedVariable => e
                    if e.varname == name
                        raise "Cyclic reference found in definition of #{name}"
                    else
                        raise
                    end
                end
            }
        elsif @variables.has_key?(name)
            @variables[name]
        elsif @parent
            @parent.value_of(name)
        else
            raise UndefinedVariable.new(name), "Interpolated variable #{name} is not defined"
        end
    end

    def each_interpolation(value)
        return value if (!value.respond_to?(:to_str) || value.empty?)
        
        # Special case: if 'value' is *only* an interpolation, avoid
        # conversion to string
        WholeMatch.each_match(value) do |data|
            return yield(data[1] || data[2])
        end

        interpolated = ''
        data = nil
        PartialMatch.each_match(value) do |data|
            varname = data[1] || data[2]
            interpolated << data.pre_match << yield(varname)
        end
        return data ? (interpolated << data.post_match) : value
    end
end


