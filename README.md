<html>
<head>
<meta charset="UTF-8">
<title>Logstash for SCAPI - input wilywebsvcs</title>
<link rel="stylesheet" href="http://logstash.net/style.css">
</head>
<body>
<div class="container">
<div class="header">

<!--main content goes here, yo!-->
<div class="content_wrapper">
<h2>wilywebsvcs</h2>
<h3> Synopsis </h3>
Connects to Wily Introscope Web Services interface, extracts metrics on a specified schedule, using a set of supplied metric selectors
<pre><code>input {
wilywebsvcs {
  <a href="#wsdl">wsdl</a> => ... # string (required)
  <a href="#username">username</a> => ... # string (required)
  <a href="#password">password</a> => ... # string (required)
  <a href="#dataSelectors">dataSelectors</a> => ... # hash (required)
  <a href="#start_time">start_time</a> => ... # string (optional), default: current time is used
  <a href="#end_time">end_time</a> => ... # string (optional), default: none
  <a href="#latency">latency</a> => ... # number (optional), default: 0 minutes
  <a href="#aggregation_interval">aggregation_interval</a> => ... # number (optional), default: 15 minutes
  <a href="#SCAWindowMarker">SCAWindowMarker</a> => ... # boolean (optional), default: false
  }
}
</code></pre>
<h3> Details </h3>
Connects to Wily Introscope Web Services interfaces, specified in the user supplied WSDL file. Uses the user supplied data selectors and time specifications to extract metric data from the Web Services interface. Some basic processing of the returned SOAP data is carried out and simple Logstash events are created and output. This plugin will be of particular use with IBM Predictive Insights
<h4>
<a name="wsdl">
wsdl
</a>
</h4>
<ul>
<li> Value type is <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#string">String</a> </li>
<li> There is no default value for this setting </li>
</ul>
<p>Specify the path to the WSDL file for this environment. This plugin has been tested with 'MetricsDataService.xml' (Built on Apr 22, 2006)  from Wily. Note: This file must be provided by the user. The local instance of this file must be edited to provide the wsdlsoap:address location information. For example, find the entry in the file corresponding to wsdlsoap:address location=   and change it appropriately for your environment. Usually, this is simply a matter of changing the host/port information in your local MetricsDataService.xml file.
</p>
<h4>
<a name="username">
username
</a>
</h4>
<ul>
<li> Value type is <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#string">String</a> </li>
<li> There is no default value for this setting</li>
</ul>
<p>
Username to connect to Introscope
</p>
<h4>
<a name="password">
password
</a>
</h4>
<ul>
<li> Value type is <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#string">String</a> </li>
<li> There is no default value for this setting</li>
</ul>
<p>
Password to connect to Introscope
</p>
<h4>
<a name="dataSelectors">
dataSelectors
</a>
</h4>
<ul>
<li> Value type is <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#hash">hash</a> </li>
<li> Default value is "" </li>
</ul>
<p>
These are the metric selector specification, used when invoking the WebService interface. Each one of the supplied rows will form the basis for selecting metrics in a SOAP request. They are arranged as groups, and within each group, sets of agent regex, metric regex and data frequency specifications. Please see your Wily Introscope MetricDataService documentation for details on allowable syntax and expected semantics. The output data will have a group attribute and value associated with it, to allow you to relate it to the individual dataSelector entry that was responsible for its creation.
<p>Use
  .... weblink coming .... 
<p>Example entries</p>
<pre><code>
 dataSelectors => {
    "GroupA"   => ["agentRegex,metricRegex,300"]
    "WWW"      => [ "hostABC,Frontends\|Apps\|WebSphere Portal Server:Response Per Interval,300",
                    "myhosts(10|11|12).*,CPU:Utilization \% \(process\),300" ]
    "Garbage"  => [ "serverX ,GC Heap:Bytes In Use,300"]
            }
</code></pre>
</p>
<h4>
<a name="start_time">
start_time (optional setting)
</a>
</h4>
<ul>
<li> Value type is <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#string">string</a> </li>
<li> There is no default value for this setting. </li>
</ul>
<p>
The plugin will start collecting from the specified time.  If start_time is not provided, the plugin will collect data from current time.

   # times format is  ISO8601 e.g.
<code>start_time => "2015-08-21T14:32:00+0000"</code>
</p>

<h4>
<a name="end_time">
end_time (optional setting)
</a>
</h4>
<ul>
<li> Value type is <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#string">string</a> </li>
<li> There is no default value for this setting. </li>
</ul>
<p>
The plugin will stop collecting from the specified time.  If end_time is not provided, the plugin will continue to collect data, moving forward, limited only by wallclock time ( it won't go past current time) and the configured latency setting

   # times format is  ISO8601 e.g.
<code>end_time => "2015-08-22T14:32:00+0000"</code>
</p>
<h4>
<a name="latency">
latency (optional setting)
</a>
</h4>
<ul>
<li> Value type is <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#number">number</a> in minutes </li>
<li> Default 0 mins meaning, run up to current wallclock time</li>
</ul>
<p>
As the plugin moves forward through time, extracting data, it will stay behind current time by the specified amount of latency. This is typically used when the data is slow to become available in Introscope, e.g. due to slow agent loads or other environmental conditions.
</p>

<h4>
<a name="aggregation_interval">
aggregation_interval (optional setting)
</a>
</h4>
<ul>
<li> Value type is <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#number">number</a> in minutes </li>
<li> Default 15mins </li>
</ul>
<p>
As the plugin moves through time, it moves forward with this interval. E.g. if it started from 12:00, with this 15min setting, it would poll data for 12:00, then 12:15, then 12:30 and so on. This is usually aligned with the Predictive Insights aggregation interval
</p>

<h4>
<a name="SCAWindowMarker">
SCAWindowMarker (optional setting)
</a>
</h4>
<ul>
<li> Value type is <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#boolean">boolean</a></li>
<li> Default false </li>
</ul>
<p>
Will send a token event down the event pipeline, corresponding to each request/response cycle. This is often used as a stream punctuator with IBM Predictive Insights, to indicate to downstream plugins (e.g. scacsv) that a set of input data can be treated atomically and processed.
</p>

</div>
<!--closes main container div-->
<div class="clear">
</div>
<div class="footer">
<p>
Hello! I'm your friendly footer. If you're actually reading this, I'm impressed.
</p>
</div>
<noscript>
<div style="display:inline;">
<img height="1" width="1" style="border-style:none;" alt="" src="//googleads.g.doubleclick.net/pagead/viewthroughconversion/985891458/?value=0&amp;guid=ON&amp;script=0"/>
</div>
</noscript>
<script src="/js/patch.js?1.4.2"></script>
</body>
</html>

