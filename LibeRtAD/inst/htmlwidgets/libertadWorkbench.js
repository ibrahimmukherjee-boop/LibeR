(function () {
  "use strict";
  var e = React.createElement;
  function list(x) { return Array.isArray(x) ? x : []; }
  function val(x, fallback) { return x === undefined || x === null || x === "" ? fallback : x; }
  function fmt(x, digits) { var n = Number(x); return isFinite(n) ? n.toFixed(digits === undefined ? 2 : digits).replace(/\.0+$/, "") : "--"; }
  function initialDarkTheme(legacyKey) {
    return window.LibeRDesign.theme.initialDark(legacyKey);
  }
  function storeTheme(dark, legacyKey) {
    window.LibeRDesign.theme.store(dark, legacyKey, false);
  }
  function emit(props, action, detail) {
    if (!window.Shiny || !window.Shiny.setInputValue) return;
    window.Shiny.setInputValue((props.inputId || "libertad_workbench") + "_event",
      Object.assign({ action: action, nonce: Date.now() }, detail || {}), { priority: "event" });
  }
  function Button(props) { return e("button", { type: "button", className: "ad-button " + val(props.className, ""), disabled: !!props.disabled, onClick: props.onClick, title: props.title, "aria-label": props.ariaLabel || props.title }, props.children); }
  function Field(props) { return e("label", { className: "ad-field" }, e("span", null, props.label), props.children, props.help ? e("small", null, props.help) : null); }
  function Check(props) { return e("label", { className: "ad-check" }, e("input", { type: "checkbox", checked: props.checked, onChange: props.onChange }), e("i", null), e("span", null, props.label)); }
  function Panel(props) { return e("section", { className: "ad-panel " + val(props.className, "") }, e("header", null, e("div", null, e("strong", null, props.title), props.subtitle ? e("span", null, props.subtitle) : null), props.actions || null), e("div", { className: "ad-panel-body" }, props.children)); }
  function Empty(props) { return e("div", { className: "ad-empty" }, e("span", null, val(props.icon, "{ }") ), e("strong", null, props.title), e("p", null, props.detail)); }
  function ThemeSwitch(props) { return e("label", { className: "ad-theme-switch", title: "Switch colour theme" }, e("span", null, props.dark ? "Dark" : "Light"), e("input", { type: "checkbox", checked: props.dark, onChange: props.onChange }), e("i", null)); }

  function TimingBars(props) {
    var rows = list(props.native && props.native.timings);
    if (!rows.length) return e(Empty, { title: "No AD benchmark yet", detail: "Choose a workload and run the native benchmark." });
    var maxLog = Math.max.apply(null, rows.map(function (r) { return Math.log10(Number(r.microseconds_per_call) + 1); }));
    return e("div", { className: "ad-bars" }, rows.map(function (r, i) {
      var width = maxLog > 0 ? 100 * Math.log10(Number(r.microseconds_per_call) + 1) / maxLog : 0;
      return e("div", { className: "ad-bar-row", key: i }, e("div", { className: "ad-bar-label" }, e("strong", null, r.operation), e("span", null, r.backend)), e("div", { className: "ad-bar-track" }, e("i", { className: String(r.backend).indexOf("LibeRtAD") >= 0 ? "native" : "reference", style: { width: width + "%" } })), e("b", null, fmt(r.microseconds_per_call, 2) + " us"));
    }));
  }
  function NativeSummary(props) {
    var nativeResult = props.native, rows = list(nativeResult && nativeResult.timings);
    if (!nativeResult) return e(Empty, { icon: "d/dx", title: "Persistent-tape benchmark", detail: "Measure recording separately from repeated values and exact derivatives." });
    var derivatives = rows.filter(function (r) { return r.backend === "LibeRtAD C++ tape" && r.operation !== "value"; });
    var fastest = derivatives.length ? derivatives.slice().sort(function(a,b){return a.microseconds_per_call-b.microseconds_per_call;})[0] : null;
    return e("div", null,
      e("div", { className: "ad-metric-grid" }, e("div", null, e("span", null, "Workload"), e("strong", null, nativeResult.label)), e("div", null, e("span", null, "Tape optimisation"), e("strong", null, nativeResult.settings.optimize ? "Enabled" : "Disabled")), e("div", null, e("span", null, "Fastest derivative"), e("strong", null, fastest ? fmt(fastest.microseconds_per_call, 2) + " us" : "--")), e("div", null, e("span", null, "Generated"), e("strong", null, nativeResult.generatedAt))),
      e(Panel, { title: "Time per call", subtitle: "Log-scaled bars; lower is faster" }, e(TimingBars, props)),
      e(Panel, { title: "Measured operations", subtitle: "Recording and repeated calls remain separate" }, e("div", { className: "ad-table-wrap" }, e("table", { className: "ad-table" }, e("thead", null, e("tr", null, ["Operation", "Backend", "Calls", "us / call", "Calls / second"].map(function (x) { return e("th", { key: x }, x); }))), e("tbody", null, rows.map(function (r, i) { return e("tr", { key: i }, e("td", null, r.operation), e("td", null, r.backend), e("td", null, r.iterations), e("td", null, fmt(r.microseconds_per_call, 3)), e("td", null, fmt(r.calls_per_second, 0))); })))))
    );
  }
  function Accuracy(props) {
    var rows = list(props.native && props.native.accuracy);
    if (!rows.length) return e(Empty, { title: "No accuracy checks", detail: "Run a native benchmark to compare CppAD results with independent R references." });
    return e(Panel, {
      title: "Numerical agreement",
      subtitle: "Maximum absolute difference at the benchmark evaluation point"
    }, e("div", { className: "ad-table-wrap" },
      e("table", { className: "ad-table" },
        e("thead", null, e("tr", null,
          e("th", null, "Check"), e("th", null, "Reference"),
          e("th", null, "Maximum absolute difference"))),
        e("tbody", null, rows.map(function (r, i) {
          var difference = Number(r.max_absolute_difference);
          return e("tr", { key: i }, e("td", null, r.check),
            e("td", null, r.reference),
            e("td", null, e("span", {
              className: difference < 1e-5 ? "ad-pass" : "ad-review"
            }, difference.toExponential(3))));
        }))
      )
    ));
  }
  function EcosystemSummary(props) {
    var result = props.ecosystem, rows = list(result && result.summary);
    if (!result) return e(Empty, { icon: "NM", title: "End-to-end benchmark", detail: props.benchmarkAvailable ? "Configure and launch the existing LibeRation/NONMEM validation harness." : "Open the GUI from a LibeR source checkout, or pass benchmark_root to libertad_gui()." });
    return e("div", null, e("div", { className: "ad-metric-grid" }, e("div", null, e("span", null, "Exit status"), e("strong", null, result.exitStatus === 0 ? "Completed" : "Failed (" + result.exitStatus + ")")), e("div", { className: "ad-wide-metric" }, e("span", null, "Output"), e("strong", { title: result.output }, result.output))), rows.length ? e(Panel, { title: "Workflow timing", subtitle: "Fresh-process end-to-end and engine-reported core time" }, e("div", { className: "ad-table-wrap" }, e("table", { className: "ad-table" }, e("thead", null, e("tr", null, ["Engine", "Workload", "Method", "End-to-end (s)", "Core (s)", "Fit (s)", "Covariance (s)"].map(function(x){return e("th",{key:x},x);}))), e("tbody", null, rows.map(function(r,i){return e("tr",{key:i},e("td",null,r.engine),e("td",null,r.workload),e("td",null,r.method),e("td",null,fmt(r.median_end_to_end_seconds,3)),e("td",null,fmt(r.median_core_seconds,3)),e("td",null,fmt(r.median_fit_seconds,3)),e("td",null,fmt(r.median_covariance_seconds,3))); }))))) : e(Empty, { title: "No successful timing rows", detail: "Inspect the runtime log and output directory." }));
  }
  function RuntimeLog(props) {
    var lines = list(props.ecosystemLog);
    return e(Panel, { title: "Runtime log", subtitle: lines.length ? lines.length + " lines" : "No background benchmark started" }, lines.length ? e("pre", { className: "ad-log" }, lines.join("\n")) : e(Empty, { title: "Log is empty", detail: "Ecosystem benchmark output will stream here while it runs." }));
  }

  function NativeConfig(props) {
    var cases = list(props.cases), selected = React.useState(cases.length ? cases[0].id : "rosenbrock"), iterations = React.useState("1000"), warmups = React.useState("50"), optimize = React.useState(true), finite = React.useState(true);
    var info = cases.filter(function(x){return x.id===selected[0];})[0];
    return e("div", null, e(Field, { label: "Workload", help: info ? info.description : "" }, e("select", { value: selected[0], onChange: function(x){selected[1](x.target.value);} }, cases.map(function(x){return e("option",{key:x.id,value:x.id},x.label);}))), e("div", { className: "ad-form-pair" }, e(Field, { label: "Requested calls" }, e("input", { type:"number",min:1,value:iterations[0],onChange:function(x){iterations[1](x.target.value);} })), e(Field, { label: "Warm-up calls" }, e("input", { type:"number",min:0,value:warmups[0],onChange:function(x){warmups[1](x.target.value);} }))), e(Check, { checked: optimize[0], onChange: function(x){optimize[1](x.target.checked);}, label: "Optimise the CppAD tape" }), e(Check, { checked: finite[0], onChange: function(x){finite[1](x.target.checked);}, label: "Include finite-difference comparator" }), e(Button, { className:"ad-primary ad-wide", disabled:!!(props.task&&props.task.running)||!!props.ecosystemRunning, onClick:function(){emit(props,"run_native",{case:selected[0],iterations:Number(iterations[0]),warmups:Number(warmups[0]),optimize:optimize[0],finite_difference:finite[0]});} }, props.task&&props.task.running ? "Benchmark running..." : "Run AD benchmark"));
  }
  function EcosystemConfig(props) {
    var profile=React.useState("smoke"),scenario=React.useState("iv-bolus"),methods=React.useState("deterministic"),engines=React.useState("LIBERATION"),repeats=React.useState("1"),warmups=React.useState("0"),covariance=React.useState(true),simulation=React.useState(true),output=React.useState(val(props.defaultOutput,""));
    var running=!!props.ecosystemRunning, taskRunning=!!(props.task&&props.task.running);
    return e("div",null,e(Field,{label:"Profile"},e("select",{value:profile[0],onChange:function(x){profile[1](x.target.value);}},["smoke","quick","standard"].map(function(x){return e("option",{key:x},x);}))),e(Field,{label:"Scenario"},e("select",{value:scenario[0],onChange:function(x){scenario[1](x.target.value);}},["iv-bolus","oral","two-compartment","three-compartment","full-omega","infusion-steady-state","iov","advan6","advan13"].map(function(x){return e("option",{key:x},x);}))),e(Field,{label:"Methods"},e("select",{value:methods[0],onChange:function(x){methods[1](x.target.value);}},e("option",{value:"deterministic"},"FO / FOCE / FOCEI / Laplace"),e("option",{value:"all"},"All supported methods"),["FO","FOCE","FOCEI","LAPLACE","ITS","IMP","SAEM"].map(function(x){return e("option",{key:x,value:x},x);}))),e(Field,{label:"Engines"},e("select",{value:engines[0],onChange:function(x){engines[1](x.target.value);}},e("option",{value:"LIBERATION"},"LibeRation only"),e("option",{value:"NONMEM,LIBERATION"},"NONMEM and LibeRation"),e("option",{value:"NONMEM"},"NONMEM only"))),e("div",{className:"ad-form-pair"},e(Field,{label:"Measured repeats"},e("input",{type:"number",min:1,value:repeats[0],onChange:function(x){repeats[1](x.target.value);}})),e(Field,{label:"Process warm-ups"},e("input",{type:"number",min:0,value:warmups[0],onChange:function(x){warmups[1](x.target.value);}}))),e(Check,{checked:covariance[0],onChange:function(x){covariance[1](x.target.checked);},label:"Include covariance"}),e(Check,{checked:simulation[0],onChange:function(x){simulation[1](x.target.checked);},label:"Include simulation"}),e(Field,{label:"Output root"},e("input",{value:output[0],onChange:function(x){output[1](x.target.value);}})),running?e(Button,{className:"ad-danger ad-wide",onClick:function(){emit(props,"stop_ecosystem",{});}},"Stop benchmark"):e(Button,{className:"ad-primary ad-wide",disabled:!props.benchmarkAvailable||taskRunning,onClick:function(){emit(props,"run_ecosystem",{profile:profile[0],scenario:scenario[0],methods:methods[0],engines:engines[0],repeats:Number(repeats[0]),process_warmups:Number(warmups[0]),covariance:covariance[0],simulation:simulation[0],output:output[0]});}},"Run ecosystem benchmark"),!props.benchmarkAvailable?e("p",{className:"ad-note"},"Repository harness not found. Pass benchmark_root to libertad_gui()."):null);
  }

  function Workbench(props) {
    var mode=React.useState("native"),tab=React.useState("summary"),dark=React.useState(function(){return initialDarkTheme("libertadTheme");}),navOpen=React.useState(false),configOpen=React.useState(false);
    var task=window.LibeRDesign.taskState.use(React,props.inputId,props.task);
    var ecosystemLog=React.useState(list(props.ecosystemLog));
    React.useEffect(function(){ecosystemLog[1](list(props.ecosystemLog));},[props.ecosystemLog]);
    React.useEffect(function(){
      if(!window.Shiny||!window.Shiny.addCustomMessageHandler)return undefined;
      window.Shiny.addCustomMessageHandler("libertad-workbench-patch",function(patch){
        window.setTimeout(function(){
          if(!patch||patch.inputId!==(props.inputId||"libertad_workbench"))return;
          if(Array.isArray(patch.ecosystemLog)){
            ecosystemLog[1](patch.ecosystemLog);
          }else if(Array.isArray(patch.ecosystemLogAppend)&&patch.ecosystemLogAppend.length){
            ecosystemLog[1](function(current){return list(current).concat(patch.ecosystemLogAppend);});
          }
        },0);
      });
      return undefined;
    },[props.inputId]);
    props=Object.assign({},props,{task:task,ecosystemLog:ecosystemLog[0]});
    React.useEffect(function(){storeTheme(dark[0],"libertadTheme");},[dark[0]]);
    React.useEffect(function(){
      function keydown(event){if(event.key==="Escape"){navOpen[1](false);configOpen[1](false);}}
      document.addEventListener("keydown",keydown);
      return function(){document.removeEventListener("keydown",keydown);};
    },[]);
    function toggle(){dark[1](!dark[0]);}
    function closeDrawers(){navOpen[1](false);configOpen[1](false);}
    var tabs=["summary","accuracy","runtime log"];
    return e("div",{className:"ad-shell "+(dark[0]?"ad-dark":"ad-light")},
      e("header",{className:"ad-header"},e("div",{className:"ad-brand"},props.icon?e("img",{src:props.icon,alt:"",className:"ad-logo"}):e("span",{className:"ad-logo-fallback"},"AD"),e("div",null,e("strong",null,"LibeRtAD"),e("span",null,"Automatic differentiation benchmark laboratory"))),e("div",{className:"ad-header-right"},e("button",{type:"button",className:"ad-drawer-toggle ad-nav-toggle","aria-label":"Open benchmark navigation","aria-expanded":navOpen[0],onClick:function(){navOpen[1](!navOpen[0]);configOpen[1](false);}},"☰"),e("button",{type:"button",className:"ad-drawer-toggle ad-config-toggle","aria-label":"Open benchmark settings","aria-expanded":configOpen[0],onClick:function(){configOpen[1](!configOpen[0]);navOpen[1](false);}},"⚙"),e("span",{className:"ad-engine-badge"},"C++17 / CppAD"),e(ThemeSwitch,{dark:dark[0],onChange:toggle}))),
      e("div",{className:"ad-message ad-message-"+val(props.status&&props.status.level,"info")},e("i",null),e("span",null,task.running?val(task.label,"Background calculation")+" is running":val(props.status&&props.status.text,"Benchmark laboratory ready")),task.running&&task.cancellable?e(Button,{className:"ad-task-cancel",onClick:function(){emit(props,"cancel_task",{id:task.id});}},"Cancel"):null),
      (navOpen[0]||configOpen[0])?e("button",{type:"button",className:"ad-drawer-backdrop","aria-label":"Close navigation and settings",onClick:closeDrawers}):null,
      e("div",{className:"ad-layout"},e("aside",{className:"ad-sidebar"+(navOpen[0]?" open":"")},e("strong",{className:"ad-kicker"},"Benchmark suite"),e("button",{className:mode[0]==="native"?"active":"",onClick:function(){mode[1]("native");tab[1]("summary");navOpen[1](false);}},e("b",null,"AD microbenchmarks"),e("span",null,"Tape recording and derivatives")),e("button",{className:mode[0]==="ecosystem"?"active":"",onClick:function(){mode[1]("ecosystem");tab[1]("summary");navOpen[1](false);}},e("b",null,"Ecosystem benchmark"),e("span",null,"LibeRation versus NONMEM")),e("div",{className:"ad-engine-card"},e("strong",null,"Engine"),e("dl",null,e("dt",null,"Backend"),e("dd",null,val(props.engineNamed&&props.engineNamed.backend,"CppAD")),e("dt",null,"Tape"),e("dd",null,props.engineNamed&&props.engineNamed.persistent_tape?"Persistent":"Unavailable"),e("dt",null,"C++"),e("dd",null,val(props.engineNamed&&props.engineNamed.cpp_standard,"17"))))),
        e("main",{className:"ad-main"},e("nav",{className:"ad-tabs"},tabs.map(function(x){var disabled=x==="accuracy"&&mode[0]!=="native";return e("button",{key:x,disabled:disabled,className:tab[0]===x?"active":"",onClick:function(){tab[1](x);}},x);})),e("div",{className:"ad-canvas"},tab[0]==="runtime log"?e(RuntimeLog,props):tab[0]==="accuracy"?e(Accuracy,props):mode[0]==="native"?e(NativeSummary,props):e(EcosystemSummary,props))),
        e("aside",{className:"ad-config"+(configOpen[0]?" open":"")},e("div",{className:"ad-config-head"},e("strong",null,mode[0]==="native"?"AD benchmark setup":"Workflow setup"),e("span",null,mode[0]==="native"?"Runs in this R session":"Runs in a background R process")),mode[0]==="native"?e(NativeConfig,props):e(EcosystemConfig,props),e("div",{className:"ad-caution"},e("strong",null,"Interpretation"),e("p",null,mode[0]==="native"?"Tiny expressions emphasize call overhead. Use trends and regression changes, not a single timing as a universal speed claim.":"End-to-end time is the operational comparison. Keep the machine idle and use standard profiles for stable conclusions.")))),
      e("footer",{className:"ad-footer"},e("span",null,"LibeRtAD v"+val(props.packageVersion,"0.7.0")),e("span",null,"Persistent R pointers / C++ execution / reproducible outputs")));
  }
  reactR.reactWidget("libertadWorkbench", "output", { LibeRtADWorkbench: Workbench }, {});
}());
