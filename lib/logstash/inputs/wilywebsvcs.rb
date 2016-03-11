# encoding: utf-8                                                              

#
# Mediate data from CA Wily Introscope via WilyWebSvcs
#
# Robert Mckeown   rmckeown@us.ibm.com
# 
#

require 'logstash/inputs/base'
require 'logstash/namespace'

require 'java' # for the java data format stuff
require 'savon'
require 'yaml'

class LogStash::Inputs::WilyWebSvcs < LogStash::Inputs::Base
  config_name "wilywebsvcs"
  milestone 1

  default :codec, "plain"

  config :wsdl, :validate => :string, :required => true
  config :username, :validate => :string, :required => true
  config :password, :validate => :string, :required => true
  config :dataSelectors, :validate => :hash, :required => true

  config :start_time, :validate => :string, :default => ""
  config :end_time,   :validate => :string, :default => ""
  config :latency,    :validate => :number, :default => 0 # minutes
  config :aggregation_interval, :validate => :number, :default => 15 # minutes
  
  # The state preservation behaviour follows that of the jdbc input plugin
  # See https://www.elastic.co/guide/en/logstash/current/plugins-inputs-jdbc.html

  # whether the previous run state should be preserved - true = delete previous state
  config :clean_run, :validate => :boolean, :default => false

  # Whether to save state or not in last_run_metatdata_path
  config :record_last_run, :validate => :boolean, :default => true

  # Whether to save satte or not in last_run_metadata_path
  config :last_run_metadata_path, :validate => :string, :default => "#{ENV['HOME']}/.logstash_wilywebsvcs_last_run"

  config :sleep_interval, :validate => :number, :default => 10 # seconds
  config :logSOAPResponse, :validate => :boolean, :default => false

  public
  def register 

    @df = java.text.SimpleDateFormat.new("yyyy-MM-dd'T'HH:mm:ssZ") # format corresponds to PI mediation format
    @wilyDF = java.text.SimpleDateFormat.new("yyyy-MM-dd'T'HH:mm:ssX")
    @wilyDF.setTimeZone(java.util.TimeZone.getTimeZone("GMT"))

    @startTime = 0
    @endTime   = 0

    # Establish start time, using configured @start_time if present, and defaulting to current time, if it is not
    if @start_time != "" then
        @startTime = @df.parse(@start_time)
        @logger.debug("Setting start time from .conf as " + @df.format(@startTime))
    else
        @startTime = java.util.Date.new
        @logger.debug("Setting start time as current time " + @df.format(@startTime))
    end    

    # load last time from file if exists and use that as the current startTime
    if @clean_run && File.exist?(@last_run_metadata_path)
      File.delete(@last_run_metadata_path)
    elsif File.exist?(@last_run_metadata_path)
      @startTime = @df.parse(YAML.load(File.read(@last_run_metadata_path)))
      @logger.debug("Using startTime from store " + @last_run_metadata_path + " " + @df.format(@startTime))
    end

    if @end_time != "" then
       @endTime = @df.parse(@end_time)
    end

    @client = Savon.client(wsdl: @wsdl,convert_request_keys_to: :none,
                                    basic_auth:[username,password],
                                    log: @logSOAPResponse, pretty_print_xml: true)
    @logger.debug("Savon client created from wsdl ")
  end
 
  private
  def decodeRefs(responseBody)
    mdr = responseBody[:get_metric_data_response]

    metricRefs = []
    rawMetricRefs = mdr[:get_metric_data_return][:get_metric_data_return]

    # Catch singleton case, hash instead of array is returned
    if rawMetricRefs.instance_of? Hash 
      metricRefs << rawMetricRefs # just add single one so we have something to iterate over
    elsif rawMetricRefs.instance_of? Array
      metricRefs = rawMetricRefs 
    end

    refs = metricRefs.collect { |e| 
        href = e[:@href].dup
        if href.start_with?("#")
          href[0] ="" 
        end
        href}
    return refs 
  end

  private
  def cleanHref( aHREF )
    href = aHREF[:@href].dup
    if href.start_with?("#")
      href[0] = ""
    end
    href 
  end

  private
  def decodeMetricData(responseBody)
   
    multiRef = responseBody[:multi_ref]

    metricDataPrepared = Hash.new
    if multiRef.instance_of? Array
      metricData = multiRef.select { |e| e.key?(:metric_data) }
      metricData.each do |e|
        rawAgentRef = e[:metric_data][:metric_data]
        href = []
        if rawAgentRef.instance_of? Hash
          href << cleanHref(rawAgentRef)
        elsif rawAgentRef.instance_of? Array
          rawAgentRef.each do | raf |
            unless raf[:@href].nil?
              href << cleanHref(raf)
            end
          end
        end
    
        metricDataPrepared[e[:@id]] =  
          {:href => href,
            :timeslice_start_time => e[:timeslice_start_time].to_s,
            :timeslice_end_time   => e[:timeslice_end_time].to_s}
      end 
      #metricDataPrepared.each do |e| 
      #  @logger.debug("metricDataPrepared = " + e.to_s) 
      #end
    end  
    return metricDataPrepared
  end

  private
  def decodeAgentData(responseBody)

    agentDataPrepared = Hash.new
    multiRef = responseBody[:multi_ref]

    if multiRef.instance_of? Array
      agentData = multiRef.reject { |e| e.key?(:metric_data)}

      agentData.each do  |e| 
        agentDataPrepared[e[:@id]] = 
          {:agent_name   => e[:agent_name],
           :metric_name  => e[:metric_name],
           :metric_value => e[:metric_value]}
      end
      #agentDataPrepared.each do |e| 
      #  @logger.debug("agentDataPrepared = " + e.to_s) 
      #end
    end
    return agentDataPrepared
  end

  private
  def marshallOut( object,dumpFile ) 
    File.open(dumpFile, 'wb') do |f|
      Marshal.dump(object,f) 
    end  
 end

  public
  def extractDataForTimestamp(targetTimestamp, interval, dataSelectors, df, wilyDF )

    @logger.debug("dataSelectors = " + dataSelectors.to_s)

    bufferedEvents = []

    dataSelectors.each do | group, selectorArray |  
      selectorArray.each do | selectorOriginal |
        @logger.debug("selectorOriginal = " + selectorOriginal)
          
        splitSelector = selectorOriginal.split(",")  
         
        agentRegex    =  splitSelector[0]
        metricRegex   =  splitSelector[1]
        dataFrequency =  splitSelector[2]

        startTime = wilyDF.format(targetTimestamp)
        endTime   = wilyDF.format(java.util.Date.new(targetTimestamp.getTime() + interval))
        soapQuery = 
              "agentRegex:"   + agentRegex + " " +
              "metricRegex:"  + metricRegex + " " +
              "dataFrequency:"+ dataFrequency + " " +
              "startTime:"    + startTime + " " +
              "endTime:"      + endTime
        @logger.debug("SOAPQuery " + soapQuery)

        response = @client.call(:get_metric_data, :message => {
          :agentRegex  => agentRegex,
          :metricRegex => metricRegex, 
          :dataFrequency => dataFrequency,
          :startTime     => startTime, #"2015-12-08T00:00:00Z"
          :endTime       => endTime # "2015-12-08T01:00:00Z"
                               })

        @logger.debug("response = " + response.to_s)
        
        refs    = decodeRefs(response.body)
        unless refs.empty? then   # only enter this block if we have some data

          begin
            metrics = decodeMetricData(response.body)          
            agents  = decodeAgentData(response.body)
          rescue Exception => e
            # Capture the returned structure so we can analyze offline
            @logger.error("Exception decoding metrics or agent data ", :exception => e)
            marshallOut(response.body,"responseBody.dmp")
            puts("response = " + response.to_xml.to_s)
            puts("soapQuery = " + soapQuery)
            exit 
          end

          @logger.debug("metrics = " + metrics.to_s)
          @logger.debug("agents = " + agents.to_s)

          # Iterate over returned results and produce Logstash events
          refs.each do |r|
            begin
              unless metrics[r].nil? 
                metrics[r][:href].each do | href |
              
                  event = LogStash::Event.new
                  event['group'] = group 
                  event['refID'] = r.to_s
                  event['timeslice_start_time']=metrics[r][:timeslice_start_time]
                  event['timeslice_end_time']=metrics[r][:timeslice_end_time]
                  agentData = agents[href]
                  event['agent_name']  = agentData[:agent_name]
                  event['metric_name'] = agentData[:metric_name]
                  event['metric_value'] = agentData[:metric_value] 

                  bufferedEvents.push(event)
                end # metrics[r].each do
              end # unless
            rescue Exception => e
              @logger.error("Exception producing Logstash event ", :exception => e)
              marshallOut(response.body,"responseBody." +Time.now.to_i.to_s+".dmp")
              puts("response = " + response.to_xml.to_s)
              puts("soapQuery = " + soapQuery)
              #exit 
            end # begin (exception block) 
          end #refs.each
        end #unless refs.empty?
      end
    end

    bufferedEvents
  end

  public
  def run(queue)

    store = "" # placeholder

    timeIncrement = @aggregation_interval * 60000 # convert supplied minutes to milliseconds


    @endTime   = @df.parse("2100-01-01T00:00:00-0000") # long time in the future. Only used if user didn't specify end time so we can run 'forever'

    latencySec = latency * 60 

    # start from the specified startTime
    targetTime = @startTime

    begin

      @logger.debug("targetTime = " + @df.format(targetTime))
      if ( targetTime < (Time.now() - latencySec) ) 

        bufferedEvents = extractDataForTimestamp(targetTime, timeIncrement, @dataSelectors, @df,@wilyDF)

        # Sort if necessary
        bufferedEvents.sort! { |a,b| a['timeslice_start_time'] <=> b['timeslice_start_time'] }

        # output all events
        bufferedEvents.each do | e |
          queue << e
        end

        bufferedEvents.clear

        # move to next time interval
        targetTime.setTime(targetTime.getTime() + timeIncrement)

        updateStateFile(@df, targetTime)

      else
        # wait a bit before trying again
        sleep(@sleep_interval)
      end

    end until(targetTime.getTime() >= @endTime.getTime())

    #finished
  end

  def updateStateFile(df, targetTime)
    if @record_last_run
      @logger.debug( "Updating statefile " + @last_run_metadata_path + " with " + df.format(targetTime))
      File.write(@last_run_metadata_path, YAML.dump(df.format(targetTime)))
    end
  end

  public
  def teardown
  end

end # class LogStash::Inputs::WilyWSDL
