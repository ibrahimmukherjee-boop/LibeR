(function () {
  "use strict";
  var e = React.createElement;
  function list(x) { return Array.isArray(x) ? x : []; }
  function val(x, fallback) { return x === undefined || x === null || x === "" ? fallback : x; }
  function num(x) { var n = Number(x); return isFinite(n) ? n : null; }
  function fmt(x, digits) { var n = Number(x); digits = typeof digits === "number" ? digits : 3; return isFinite(n) ? n.toFixed(digits).replace(/\.0+$/, "") : "--"; }
  function initialDarkTheme(legacyKey) {
    return window.LibeRDesign.theme.initialDark(legacyKey);
  }
  function storeTheme(dark, legacyKey) {
    window.LibeRDesign.theme.store(dark, legacyKey, false);
  }
  function useDialogFocus(onClose) {
    var dialog = React.useRef(null), close = React.useRef(onClose);
    close.current = onClose;
    React.useEffect(function () {
      var prior = document.activeElement, node = dialog.current;
      function items() { return node ? Array.prototype.slice.call(node.querySelectorAll('button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),a[href],[tabindex]:not([tabindex="-1"])')) : []; }
      function keydown(event) {
        if (event.key === "Escape") { event.preventDefault(); close.current(); return; }
        if (event.key !== "Tab" || !node) return;
        var candidates = items();
        if (!candidates.length) { event.preventDefault(); node.focus(); return; }
        if (event.shiftKey && document.activeElement === candidates[0]) { event.preventDefault(); candidates[candidates.length - 1].focus(); }
        else if (!event.shiftKey && document.activeElement === candidates[candidates.length - 1]) { event.preventDefault(); candidates[0].focus(); }
      }
      document.addEventListener("keydown", keydown);
      window.setTimeout(function () { var candidates = items(); (candidates[0] || node).focus(); }, 0);
      return function () { document.removeEventListener("keydown", keydown); if (prior && prior.focus) prior.focus(); };
    }, []);
    return dialog;
  }
  function emit(props, action, detail) {
    if (!window.Shiny || !window.Shiny.setInputValue) return;
    window.Shiny.setInputValue((props.inputId || "liberality_workbench") + "_event",
      Object.assign({ action: action, nonce: Date.now() }, detail || {}), { priority: "event" });
  }
  function Button(p) { return e("button", { type: "button", className: "ly-button " + val(p.className, ""), disabled: !!p.disabled, title: p.title, "aria-label": p.ariaLabel || p.title, onClick: p.onClick }, p.icon ? e("span", { className: "ly-button-icon", "aria-hidden": "true" }, p.icon) : null, p.children); }
  function Badge(p) { return e("span", { className: "ly-badge ly-badge-" + val(p.tone, "neutral") }, p.children); }
  function Panel(p) { return e("section", { className: "ly-panel " + val(p.className, "") }, e("header", { className: "ly-panel-head" }, e("div", null, e("strong", null, p.title), p.subtitle ? e("span", null, p.subtitle) : null), p.actions || null), e("div", { className: "ly-panel-body" }, p.children)); }
  function Empty(p) { return e("div", { className: "ly-empty" }, e("span", null, val(p.icon, "◇")), e("strong", null, p.title), e("p", null, p.detail)); }
  function Logo() { return e("span", { className: "ly-logo ly-logo-fallback", "aria-hidden": "true" }, "L"); }
  function Modal(p) { var dialog = useDialogFocus(p.onClose); return e("div", { className: "ly-modal-layer", onMouseDown: function (x) { if (x.target === x.currentTarget) p.onClose(); } }, e("section", { ref: dialog, tabIndex: -1, className: "ly-modal " + val(p.className, ""), role: "dialog", "aria-modal": "true", "aria-label": p.title }, e("header", null, e("div", null, e("strong", null, p.title), p.subtitle ? e("span", null, p.subtitle) : null), e(Button, { className: "ly-icon", ariaLabel: "Close", onClick: p.onClose }, "×")), e("div", { className: "ly-modal-body" }, p.children))); }
  function Field(p) { return e("label", { className: "ly-field " + val(p.className, "") }, e("span", null, p.label), p.children, p.help ? e("small", null, p.help) : null); }
  function Status(p) { var s = p.status || {}, task = s.task || {}; return e("div", { className: "ly-status ly-status-" + val(s.level, "info") }, e("i", null), e("span", null, task.running ? val(task.label, "Background calculation") + " is running" : val(s.text, "Ready")), task.running && task.cancellable ? e(Button, { className: "ly-task-cancel", onClick: function () { emit({ inputId: s.inputId }, "cancel_task", { id: task.id }); } }, "Cancel") : null); }
  function Metric(p) { return e("div", { className: "ly-metric" }, e("span", null, p.label), e("strong", null, p.value), p.detail ? e("small", null, p.detail) : null); }
  function Table(p) { var rows = list(p.rows); if (!rows.length) return e(Empty, { title: val(p.empty, "No results"), detail: "Run the corresponding analysis to populate this view." }); var cols = p.columns || Object.keys(rows[0]); return e("div", { className: "ly-table-wrap" }, e("table", { className: "ly-table" }, e("thead", null, e("tr", null, cols.map(function (c) { return e("th", { key: c.key || c }, c.label || c); }))), e("tbody", null, rows.map(function (r, i) { return e("tr", { key: i }, cols.map(function (c) { var key = c.key || c, value = r[key]; if (c.format) value = c.format(value, r); return e("td", { key: key }, value === null || value === undefined ? "--" : String(value)); })); })))); }
  function ArmModal(p) {
    var arm = p.arm;
    var size = React.useState(String(arm.size));
    var times = React.useState(list(arm.samplingTimes).join(", "));
    var dose0 = list(arm.doses)[0] || {};
    var dose = React.useState(String(val(dose0.AMT, 0)));
    return e(Modal, { title: "Edit " + arm.name, subtitle: "Elementary design and exact allocation", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Subjects" }, e("input", { type: "number", min: 0, value: size[0], onChange: function (x) { size[1](x.target.value); } })),
        e(Field, { label: "First dose amount" }, e("input", { type: "number", min: 0, step: "any", value: dose[0], onChange: function (x) { dose[1](x.target.value); } })),
        e(Field, { label: "Sampling times", className: "ly-span-2", help: "Comma-separated hours; keep the same number of samples." }, e("input", { value: times[0], onChange: function (x) { times[1](x.target.value); } })),
        e("footer", { className: "ly-modal-actions ly-span-2" },
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, { className: "ly-primary", onClick: function () { emit(p.owner, "edit_arm", { id: arm.id, size: size[0], times: times[0], dose: dose[0] }); p.onClose(); } }, "Apply design"))));
  }
  function OptimiseModal(p) {
    var method = React.useState("auto");
    var maxit = React.useState("40");
    return e(Modal, { title: "Optimise design", subtitle: "Continuous, discrete, integer, and hybrid variables", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Algorithm" }, e("select", { value: method[0], onChange: function (x) { method[1](x.target.value); } }, ["auto", "L-BFGS-B", "Nelder-Mead", "pso", "coordinate_exchange", "hybrid", "multiplicative", "fedorov_wynn"].map(function (x) { return e("option", { key: x, value: x }, x); }))),
        e(Field, { label: "Maximum iterations" }, e("input", { type: "number", min: 1, value: maxit[0], onChange: function (x) { maxit[1](x.target.value); } })),
        e("div", { className: "ly-callout ly-span-2" }, "The selected criterion, all declared constraints, and every design scenario are retained in the run record."),
        e("footer", { className: "ly-modal-actions ly-span-2" },
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, { className: "ly-primary", disabled: !list(p.owner.variables).length && method[0] !== "multiplicative" && method[0] !== "fedorov_wynn", onClick: function () { emit(p.owner, "optimise", { method: method[0], maxit: maxit[0] }); p.onClose(); } }, "Start optimisation"))));
  }
  function SimulateModal(p) {
    var n = React.useState("20");
    var fit = React.useState(false);
    var method = React.useState("FOCEI");
    return e(Modal, { title: "Simulate complete trials", subtitle: "Empirical operating-characteristic assessment", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Replicated trials" }, e("input", { type: "number", min: 1, value: n[0], onChange: function (x) { n[1](x.target.value); } })),
        e(Field, { label: "Analysis method" }, e("select", { value: method[0], disabled: !fit[0], onChange: function (x) { method[1](x.target.value); } }, ["FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "IMP", "SAEM", "BAYES"].map(function (x) { return e("option", { key: x }, x); }))),
        e("label", { className: "ly-check ly-span-2" }, e("input", { type: "checkbox", checked: fit[0], onChange: function (x) { fit[1](x.target.checked); } }), e("span", null, "Refit every simulated trial (substantially slower)")),
        e("footer", { className: "ly-modal-actions ly-span-2" },
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, { className: "ly-primary", onClick: function () { emit(p.owner, "simulate", { n: n[0], fit: fit[0], method: method[0] }); p.onClose(); } }, "Run simulations"))));
  }
  function FileModal(p) { var path = React.useState(p.defaultPath || "LibeRality-design.rds"); return e(Modal, { title: p.title, subtitle: p.subtitle, onClose: p.onClose }, e(Field, { label: "Local path", help: "The R process must have access to this path." }, e("input", { value: path[0], autoFocus: true, onChange: function (x) { path[1](x.target.value); } })), e("footer", { className: "ly-modal-actions" }, e(Button, { onClick: p.onClose }, "Cancel"), e(Button, { className: "ly-primary", onClick: function () { emit(p.owner, p.action, { path: path[0] }); p.onClose(); } }, p.button))); }
  function SchedulePlot(p) { var arms = list(p.arms); if (!arms.length) return null; var all = [].concat.apply([], arms.map(function (a) { return list(a.samplingTimes).concat(list(a.doses).map(function (d) { return Number(d.TIME); })); })).filter(isFinite); var min = Math.min.apply(null, all.concat([0])), max = Math.max.apply(null, all.concat([1])); if (max <= min) max = min + 1; function x(t) { return 145 + (Number(t) - min) / (max - min) * 720; } var height = 70 + arms.length * 72; return e("div", { className: "ly-chart" }, e("svg", { viewBox: "0 0 920 " + height, role: "img", "aria-label": "Study arm schedule" }, arms.map(function (arm, i) { var y = 55 + i * 72; return e("g", { key: arm.id }, e("text", { x: 15, y: y + 5, className: "ly-chart-name" }, arm.name), e("line", { x1: 145, y1: y, x2: 865, y2: y, className: "ly-axis" }), list(arm.doses).map(function (d, j) { return e("g", { key: "d" + j }, e("line", { x1: x(d.TIME), y1: y - 22, x2: x(d.TIME), y2: y + 22, className: "ly-dose" }), e("text", { x: x(d.TIME) + 4, y: y - 25, className: "ly-chart-label" }, fmt(d.AMT, 0))); }), list(arm.samplingTimes).map(function (t, j) { return e("circle", { key: "s" + j, cx: x(t), cy: y, r: 6, className: "ly-sample" }); })); }), e("text", { x: 145, y: height - 5, className: "ly-chart-label" }, fmt(min, 1) + " h"), e("text", { x: 840, y: height - 5, className: "ly-chart-label" }, fmt(max, 1) + " h"))); }
  function BarChart(p) { var rows = list(p.rows).filter(function (r) { return num(r[p.valueKey]) !== null; }); if (!rows.length) return e(Empty, { title: "No precision results", detail: "Evaluate the design first." }); var max = Math.max.apply(null, rows.map(function (r) { return Math.abs(Number(r[p.valueKey])); }).concat([1])); return e("div", { className: "ly-bars" }, rows.map(function (r) { var width = Math.min(100, Math.abs(Number(r[p.valueKey])) / max * 100); return e("div", { className: "ly-bar-row", key: r.parameter || r.name }, e("span", null, r.parameter || r.name), e("div", null, e("i", { style: { width: width + "%" } })), e("strong", null, fmt(r[p.valueKey], 2) + val(p.suffix, ""))); })); }
  function TracePlot(p) { var rows = list(p.rows).filter(function (r) { return num(r.criterion) !== null; }); if (!rows.length) return e(Empty, { title: "No optimisation trace", detail: "Run an optimisation to inspect convergence." }); var vals = rows.map(function (r) { return Number(r.criterion); }), min = Math.min.apply(null, vals), max = Math.max.apply(null, vals); if (max === min) max = min + 1; function x(i) { return 50 + i / Math.max(1, rows.length - 1) * 810; } function y(v) { return 220 - (v - min) / (max - min) * 165; } var path = vals.map(function (v, i) { return (i ? "L" : "M") + x(i) + " " + y(v); }).join(" "); return e("div", { className: "ly-chart" }, e("svg", { viewBox: "0 0 900 260" }, e("line", { x1: 50, y1: 220, x2: 860, y2: 220, className: "ly-axis" }), e("path", { d: path, className: "ly-trace" }), e("text", { x: 55, y: 42, className: "ly-chart-label" }, fmt(max, 3)), e("text", { x: 55, y: 238, className: "ly-chart-label" }, fmt(min, 3)))); }
  function ModelDiagram(p) {
    var compartments = list(p.diagram && p.diagram.compartments);
    if (!compartments.length) return e(Empty, { title: "No compartment diagram", detail: "The model is defined through likelihood or algorithm code." });
    var width = 760, gap = width / (compartments.length + 1);
    return e("div", { className: "ly-model-diagram" },
      e("svg", { viewBox: "0 0 760 190", role: "img", "aria-label": "Model compartment diagram" },
        compartments.map(function (c, i) {
          var x = gap * (i + 1), y = 92;
          return e("g", { key: c.id },
            i ? e("line", { x1: gap * i + 62, y1: y, x2: x - 62, y2: y, className: "ly-model-flow" }) : null,
            e("rect", { x: x - 60, y: y - 36, width: 120, height: 72, rx: 18, className: "ly-model-compartment" }),
            e("text", { x: x, y: y - 2, textAnchor: "middle", className: "ly-model-name" }, c.name),
            e("text", { x: x, y: y + 18, textAnchor: "middle", className: "ly-model-state" }, c.state),
            c.dose ? e("text", { x: x, y: 28, textAnchor: "middle", className: "ly-model-marker" }, "DOSE") : null,
            c.observe ? e("text", { x: x, y: 164, textAnchor: "middle", className: "ly-model-marker" }, "OBSERVE") : null);
        })));
  }
  function ModelSummary(p) {
    var model = p.model || {};
    var chooser = React.useState(false);
    React.useEffect(function () { if (p.browser && p.browser.applied) chooser[1](false); },
      [p.browser && p.browser.applied]);
    return e("div", { className: "ly-model-summary" },
      e("div", { className: "ly-model-headline" },
        e("div", null, e("small", null, val(model.source, "Model")), e("h3", null, val(model.name, "Unnamed model")), e("p", null, val(model.family, ""))),
        e("div", null, e(Badge, { tone: "accent" }, "ADVAN" + val(model.advan, "-") + " / TRANS" + val(model.trans, "-")), e(Badge, null, val(model.parameterSource, "parameter values")),
          p.browser ? e(Button, { className: "ly-primary", onClick: function () { chooser[1](true); } }, "Change model") : null)),
      e(ModelDiagram, { diagram: model.diagram }),
      chooser[0] && p.browser ? e(ModelBrowserModal, { owner: p.owner, browser: p.browser, onClose: function () { chooser[1](false); } }) : null);
  }
  function ModelBrowserModal(p) {
    var catalogue = p.browser.catalogue || {}, records = list(catalogue.records);
    var source = React.useState("builtin"), query = React.useState(""), drafts = React.useState(false);
    var controlPath = React.useState("");
    var selected = React.useState(val(p.browser.selectedKey, ""));
    var covariates = React.useState({});
    var preview = p.browser.preview;
    React.useEffect(function () {
      selected[1](val(p.browser.selectedKey, selected[0]));
      var next = {};
      list(preview && preview.compatibility && preview.compatibility.requiredCovariates).forEach(function (x) { next[x.name] = String(val(x.suggested, "")); });
      covariates[1](next);
    }, [p.browser.selectedKey, preview && preview.hash]);
    var shown = records.filter(function (r) {
      if (r.source !== source[0]) return false;
      if (source[0] === "liberary" && !drafts[0] && !r.reviewed) return false;
      var haystack = [r.label, r.subtitle, r.group, r.family, r.status].join(" ").toLowerCase();
      return haystack.indexOf(query[0].toLowerCase()) >= 0;
    });
    var selectedRecord = records.filter(function (r) { return r.key === selected[0]; })[0];
    var message = (catalogue.messages || {})[source[0]];
    function choose(record) {
      selected[1](record.key);
      emit(p.owner, "model_preview", { key: record.key });
    }
    return e(Modal, { className: "ly-model-modal", title: "Choose structural model", subtitle: "Use a template, a LibeRation model version or run, or a reviewed LibeRary entry", onClose: p.onClose },
      e("div", { className: "ly-model-browser" },
        e("div", { className: "ly-model-source-tabs" },
          [["builtin", "Built-in"], ["liberation", "LibeRation"], ["liberary", "LibeRary"], ["control", "Control stream"]].map(function (item) {
            return e("button", { type: "button", key: item[0], className: source[0] === item[0] ? "active" : "", onClick: function () { source[1](item[0]); selected[1](""); } }, item[1]);
          })),
        e("div", { className: "ly-model-browser-grid" },
          e("aside", { className: "ly-model-filter" },
            source[0] === "control" ? e("div", { className: "ly-stack" },
              e(Field, { label: "Control-stream path", help: "The R process must be able to read this file." }, e("input", { value: controlPath[0], placeholder: "model.ctl", onChange: function (x) { controlPath[1](x.target.value); } })),
              e(Button, { className: "ly-primary", disabled: !controlPath[0], onClick: function () { var key = "control:" + controlPath[0]; selected[1](key); emit(p.owner, "model_control_preview", { path: controlPath[0] }); } }, "Preview control stream")) :
              e(Field, { label: "Find a model" }, e("input", { type: "search", value: query[0], placeholder: "Name, compound, family…", onChange: function (x) { query[1](x.target.value); } })),
            source[0] === "liberary" ? e("label", { className: "ly-check" }, e("input", { type: "checkbox", checked: drafts[0], onChange: function (x) { drafts[1](x.target.checked); } }), e("span", null, "Include draft entries")) : null,
            e("p", { className: "ly-muted" }, source[0] === "builtin" ? "Curated templates supplied with LibeRation." : source[0] === "liberation" ? "Versions use initial values; completed estimation runs use final estimates." : source[0] === "liberary" ? "Reviewed or qualified entries are shown by default." : "NONMEM control streams are parsed and validated before they can be used.")),
          e("section", { className: "ly-model-candidates" },
            source[0] === "control" ? e(Empty, { title: "Import a control stream", detail: "Enter a .ctl or .mod path to preview its parsed model and compatibility with this design." }) : shown.length ? shown.map(function (record) {
              return e("button", { type: "button", key: record.key, className: "ly-model-candidate " + (selected[0] === record.key ? "active" : ""), onClick: function () { choose(record); } },
                e("small", null, val(record.group, record.source)),
                e("strong", null, record.label),
                e("span", null, val(record.subtitle, record.family)),
                e("footer", null, record.status ? e(Badge, { tone: record.reviewed ? "success" : "warning" }, record.status) : null,
                  record.advan !== null && record.advan !== undefined && record.advan !== "" && record.advan !== "null" && record.advan !== "NA" && isFinite(Number(record.advan)) ? e("em", null, "ADVAN" + record.advan + " / TRANS" + record.trans) : null));
            }) : e(Empty, { title: "No matching models", detail: message || "Adjust the search or source filter." })),
          e("section", { className: "ly-model-preview" },
            p.browser.busy ? e("div", { className: "ly-model-loading" }, e("i", null), e("span", null, "Loading model metadata…")) :
            p.browser.error ? e("div", { className: "ly-stack" }, e("div", { className: "ly-callout ly-callout-warning" }, p.browser.error), e(Button, { onClick: function () { choose(selectedRecord); } }, "Try again")) :
            preview && ((selectedRecord && selectedRecord.key === selected[0]) || (source[0] === "control" && String(selected[0]).indexOf("control:") === 0)) ? e("div", { className: "ly-stack" },
              e(ModelSummary, { model: preview }),
              e("div", { className: "ly-preview-facts" },
                e("div", null, e("span", null, "Source"), e("strong", null, preview.sourceLabel)),
                e("div", null, e("span", null, "Parameters"), e("strong", null, list(preview.parameters).length)),
                e("div", null, e("span", null, "Dose / observation"), e("strong", null, preview.doseCmt + " / " + preview.observationCmt))),
              list(preview.compatibility && preview.compatibility.warnings).map(function (warning, i) { return e("div", { className: "ly-callout ly-callout-warning", key: i }, warning); }),
              list(preview.compatibility && preview.compatibility.requiredCovariates).length ? e("div", { className: "ly-covariate-map" },
                e("strong", null, "Design covariate values"),
                list(preview.compatibility.requiredCovariates).map(function (item) {
                  return e(Field, { key: item.name, label: item.name }, e("input", { type: "number", step: "any", value: val(covariates[0][item.name], ""), onChange: function (x) { var next = Object.assign({}, covariates[0]); next[item.name] = x.target.value; covariates[1](next); } }));
                })) : null,
              e("footer", { className: "ly-modal-actions" },
                e(Button, { onClick: p.onClose }, "Cancel"),
                e(Button, { className: "ly-primary", disabled: p.browser.busy, onClick: function () { emit(p.owner, "model_apply", { key: selected[0], covariates: covariates[0] }); } }, "Use this model"))) :
            e(Empty, { title: "Select a model", detail: "The structural definition, parameter source, compartments, and compatibility checks will appear here." })))));
  }
  function App(props) {
    var stored = initialDarkTheme("LibeRality.theme");
    var dark = React.useState(stored), tab = React.useState("overview"), modal = React.useState(null), selectedArm = React.useState(list(props.arms)[0] ? props.arms[0].id : null);
    var modelBrowser = React.useState(props.modelBrowser || { catalogue: { records: [], messages: {} }, preview: null, selectedKey: "", busy: false });
    var task = window.LibeRDesign.taskState.use(React, props.inputId, props.task);
    props.status = Object.assign({}, props.status || {}, {
      task: task, inputId: props.inputId
    });
    React.useEffect(function () { storeTheme(dark[0], "LibeRality.theme"); }, [dark[0]]);
    React.useEffect(function () {
      function update(event) {
        var detail = event.detail || {};
        modelBrowser[1](function (current) {
          return Object.assign({}, current, detail, {
            catalogue: detail.catalogue || current.catalogue
          });
        });
        if (detail.applied) modal[1](null);
      }
      window.addEventListener("liberality:model-browser", update);
      return function () { window.removeEventListener("liberality:model-browser", update); };
    }, []);
    var design = props.design || {}, evaluation = props.evaluation || {}, info = evaluation.information || {}, optimisation = props.optimisation || {}, simulation = props.simulation;
    var arm = list(props.arms).filter(function (x) { return x.id === selectedArm[0]; })[0] || list(props.arms)[0];
    var tabs = [["overview", "Overview"], ["model", "Model"], ["schedule", "Schedule"], ["precision", "Precision"], ["robustness", "Robustness"], ["optimisation", "Optimisation"], ["simulation", "Simulation"]];
    function body() {
      if (tab[0] === "overview") return e("div", { className: "ly-stack" }, e("div", { className: "ly-metric-grid" }, e(Metric, { label: "Subjects", value: fmt(design.subjects, 0), detail: list(props.arms).length + " arms" }), e(Metric, { label: "Expected cost", value: fmt(design.cost, 0), detail: "declared units" }), e(Metric, { label: "Criterion", value: val(props.criterion && props.criterion.type, "D"), detail: val(props.criterion && props.criterion.direction, "maximise") }), e(Metric, { label: "Information rank", value: info.rank === undefined ? "Not evaluated" : info.rank + "/" + info.dimension, detail: info.condition ? "condition " + fmt(info.condition, 2) : "" })), e(Panel, { title: "Clinical trial architecture", subtitle: design.description }, e(SchedulePlot, { arms: props.arms })), e(Panel, { title: "Declared constraints", subtitle: "Operational and statistical feasibility" }, e(Table, { rows: props.constraints, columns: [{ key: "name", label: "Constraint" }, { key: "value", label: "Value", format: fmt }, { key: "limit", label: "Limit", format: fmt }, { key: "feasible", label: "Status", format: function (x) { return x ? "Feasible" : "Violated"; } }] })));
      if (tab[0] === "model") return e("div", { className: "ly-stack" },
        e(Panel, { title: "Structural and statistical model", subtitle: "The model is copied into this design with immutable provenance" },
          e(ModelSummary, { model: props.model, owner: props, browser: modelBrowser[0] })),
        e("div", { className: "ly-two" },
          e(Panel, { title: "Model provenance", subtitle: val(props.model.source, "") },
            e("div", { className: "ly-inspect-list" },
              e("div", null, e("span", null, "Source record"), e("strong", null, val(props.model.sourceLabel, "Built-in"))),
              e("div", null, e("span", null, "Parameter source"), e("strong", null, val(props.model.parameterSource, "template values"))),
              e("div", null, e("span", null, "Model hash"), e("strong", { className: "ly-hash" }, val(props.model.hash, "").slice(0, 16))),
              e("div", null, e("span", null, "Covariates"), e("strong", null, list(props.model.covariates).join(", ") || "None")))),
          e(Panel, { title: "Outcomes", subtitle: "Statistical observation model" },
            e(Table, { rows: props.model.outcomes, columns: [{ key: "name", label: "Outcome" }, { key: "family", label: "Family" }, { key: "dvid", label: "DVID" }] }))),
        e(Panel, { title: "Nominal parameter values", subtitle: val(props.model.parameterSource, "") },
          e(Table, { rows: props.model.parameters, columns: [{ key: "type", label: "Type" }, { key: "name", label: "Parameter" }, { key: "value", label: "Value", format: fmt }, { key: "lower", label: "Lower", format: fmt }, { key: "upper", label: "Upper", format: fmt }, { key: "fixed", label: "Fixed", format: function (x) { return x ? "Yes" : "No"; } }] })));
      if (tab[0] === "schedule") return e("div", { className: "ly-stack" }, e(Panel, { title: "Dose and observation schedule", subtitle: "Dose markers are vertical; samples are circular" }, e(SchedulePlot, { arms: props.arms })), e("div", { className: "ly-card-grid" }, list(props.arms).map(function (a) { return e("article", { className: "ly-arm-card", key: a.id, onClick: function () { selectedArm[1](a.id); } }, e("header", null, e("strong", null, a.name), e(Badge, { tone: a.id === selectedArm[0] ? "accent" : "neutral" }, a.size + " subjects")), e("p", null, a.samples + " samples per subject · " + a.population), e("small", null, list(a.samplingTimes).map(function (x) { return fmt(x, 2); }).join(", ") + " h"), e(Button, { onClick: function (ev) { ev.stopPropagation(); selectedArm[1](a.id); modal[1]("arm"); } }, "Edit arm")); })));
      if (tab[0] === "precision") return e("div", { className: "ly-two" }, e(Panel, { title: "Expected relative standard errors", subtitle: val(info.scenario, "Nominal scenario") }, e(BarChart, { rows: evaluation.precision, valueKey: "rse", suffix: "%" })), e(Panel, { title: "Criterion values", subtitle: "Direction is explicit for every objective" }, e(Table, { rows: evaluation.criteria, columns: [{ key: "name", label: "Criterion" }, { key: "type", label: "Type" }, { key: "value", label: "Value", format: function (x) { return fmt(x, 5); } }, { key: "direction", label: "Direction" }] })));
      if (tab[0] === "robustness") return e("div", { className: "ly-two" }, e(Panel, { title: "Design scenarios", subtitle: "Parameter and operational uncertainty" }, e(Table, { rows: props.scenarios, columns: [{ key: "name", label: "Scenario" }, { key: "probability", label: "Weight", format: function (x) { return fmt(100 * x, 1) + "%"; } }, { key: "adherence", label: "Adherence", format: function (x) { return fmt(100 * x, 0) + "%"; } }, { key: "dropout", label: "Dropout", format: function (x) { return fmt(100 * x, 0) + "%"; } }, { key: "missedSample", label: "Missed", format: function (x) { return fmt(100 * x, 0) + "%"; } }] })), e(Panel, { title: "Information diagnostics", subtitle: "Numerical transparency" }, info.rank === undefined ? e(Empty, { title: "Not evaluated", detail: "Run an evaluation to calculate scenario information." }) : e("div", { className: "ly-diagnostics" }, e(Metric, { label: "Log determinant", value: fmt(info.logDeterminant, 4) }), e(Metric, { label: "Condition number", value: fmt(info.condition, 3) }), e("p", null, val(info.diagnostics && info.diagnostics.method, "")), e("p", null, "Prediction derivatives: " + val(info.diagnostics && info.diagnostics.prediction_derivatives, "")))));
      if (tab[0] === "optimisation") return e("div", { className: "ly-stack" }, e(Panel, { title: "Optimisation convergence", subtitle: optimisation.method ? optimisation.method + " · " + optimisation.evaluations + " evaluations" : "No optimisation has run" }, e(TracePlot, { rows: optimisation.trace })), e(Panel, { title: "Optimisable variables", subtitle: "Current values and permitted design space" }, e(Table, { rows: props.variables, columns: [{ key: "name", label: "Variable" }, { key: "target", label: "Target" }, { key: "arm", label: "Arm" }, { key: "current", label: "Current", format: fmt }, { key: "lower", label: "Lower", format: fmt }, { key: "upper", label: "Upper", format: fmt }, { key: "type", label: "Type" }] })));
      return e("div", { className: "ly-stack" }, e(Panel, { title: "Empirical trial simulation", subtitle: simulation ? simulation.n + " replicated trials in " + fmt(simulation.elapsed, 2) + " seconds" : "Not run" }, simulation ? e("div", null, e("div", { className: "ly-metric-grid" }, e(Metric, { label: "Trials", value: simulation.n }), e(Metric, { label: "Analysis", value: simulation.method }), e(Metric, { label: "Convergence", value: simulation.convergence === null || simulation.convergence === undefined ? "Not fitted" : fmt(100 * simulation.convergence, 1) + "%" })), e(Table, { rows: simulation.estimates, columns: [{ key: "parameter", label: "Parameter" }, { key: "mean", label: "Mean", format: fmt }, { key: "bias", label: "Bias", format: fmt }, { key: "rmse", label: "RMSE", format: fmt }] })) : e(Empty, { title: "No trial simulations", detail: "Simulate complete studies to verify theoretical information and operational robustness." })));
    }
    return e("div", { className: "ly-app " + (dark[0] ? "ly-dark" : "ly-light") }, e("header", { className: "ly-header" }, e("div", { className: "ly-brand" }, props.icon ? e("img", { src: props.icon, alt: "" }) : e(Logo), e("div", null, e("strong", null, "LibeRality"), e("span", null, "Model-informed optimal trial design"))), e("div", { className: "ly-header-meta" }, e(Badge, { tone: "warning" }, "Research & teaching"), e("span", null, "v" + val(props.packageVersion, "0.1.0")), e("label", { className: "ly-switch" }, e("span", null, dark[0] ? "Dark" : "Light"), e("input", { type: "checkbox", checked: dark[0], onChange: function (x) { dark[1](x.target.checked); } }), e("i", null)))), e(Status, { status: props.status }), e("div", { className: "ly-layout" }, e("aside", { className: "ly-sidebar" }, e("div", { className: "ly-project" }, e("small", null, "ACTIVE DESIGN"), e("strong", null, val(design.name, "Untitled design")), e("span", null, "ADVAN" + val(design.advan, "-") + " / TRANS" + val(design.trans, "-"))), e("nav", { className: "ly-actions" }, e(Button, { className: "ly-primary", icon: "＋", onClick: function () { modal[1]("arm"); } }, "Edit selected arm"), e(Button, { icon: "◎", onClick: function () { emit(props, "evaluate"); } }, "Evaluate design"), e(Button, { icon: "↗", onClick: function () { modal[1]("optimise"); } }, "Optimise design"), e(Button, { icon: "∿", onClick: function () { modal[1]("simulate"); } }, "Simulate trials"), props.queueAvailable ? e(Button, { icon: "⇧", onClick: function () { emit(props, "queue", { operation: "optimise", method: "auto" }); } }, "Submit to queue") : null), e("div", { className: "ly-side-section" }, e("label", null, "Design criterion"), e("select", { value: props.criterion && props.criterion.type, onChange: function (x) { emit(props, "set_criterion", { type: x.target.value }); } }, list(props.criterionTypes).map(function (x) { return e("option", { key: x, value: x }, x); }))), e("div", { className: "ly-side-section" }, e("label", null, "Arms"), list(props.arms).map(function (a) { return e("button", { className: a.id === selectedArm[0] ? "active" : "", key: a.id, onClick: function () { selectedArm[1](a.id); } }, e("span", null, a.name), e("small", null, a.size)); })), e("div", { className: "ly-side-footer" }, e(Button, { className: "ly-quiet", onClick: function () { modal[1]("save"); } }, "Save"), e(Button, { className: "ly-quiet", onClick: function () { modal[1]("load"); } }, "Load"), e(Button, { className: "ly-quiet", onClick: function () { modal[1]("report"); } }, "Report"), e(Button, { className: "ly-danger-quiet", onClick: function () { emit(props, "reset"); } }, "Reset"))), e("main", { className: "ly-main" }, e("nav", { className: "ly-tabs" }, tabs.map(function (t) { return e("button", { key: t[0], className: tab[0] === t[0] ? "active" : "", onClick: function () { tab[1](t[0]); } }, t[1]); })), e("div", { className: "ly-content" }, body())), e("aside", { className: "ly-inspector" }, e("header", null, e("small", null, "DESIGN INSPECTOR"), e("strong", null, arm ? arm.name : "Study")), arm ? e("div", { className: "ly-inspect-list" }, e("div", null, e("span", null, "Subjects"), e("strong", null, arm.size)), e("div", null, e("span", null, "Samples"), e("strong", null, arm.samples)), e("div", null, e("span", null, "Population"), e("strong", null, arm.population)), e("div", null, e("span", null, "Sample volume"), e("strong", null, fmt(arm.sampleVolume, 1)))) : null, e("h4", null, "Endpoints"), list(props.endpoints).map(function (x) { return e("div", { className: "ly-endpoint", key: x.id }, e("strong", null, x.name), e("span", null, x.type + " · DVID " + x.dvid)); }), e("h4", null, "Reproducibility"), e("p", { className: "ly-muted" }, "Every result retains model, design, scenario, criterion, seed, version, and numerical diagnostics."))), modal[0] === "arm" && arm ? e(ArmModal, { owner: props, arm: arm, onClose: function () { modal[1](null); } }) : null, modal[0] === "optimise" ? e(OptimiseModal, { owner: props, onClose: function () { modal[1](null); } }) : null, modal[0] === "simulate" ? e(SimulateModal, { owner: props, onClose: function () { modal[1](null); } }) : null, modal[0] === "save" ? e(FileModal, { owner: props, action: "save", title: "Save design", subtitle: "Store the complete versioned design object", button: "Save", defaultPath: "LibeRality-design.rds", onClose: function () { modal[1](null); } }) : null, modal[0] === "load" ? e(FileModal, { owner: props, action: "load", title: "Load design", subtitle: "Open a trusted LibeRality RDS design", button: "Load", defaultPath: "LibeRality-design.rds", onClose: function () { modal[1](null); } }) : null, modal[0] === "report" ? e(FileModal, { owner: props, action: "report", title: "Generate report", subtitle: "Write a self-contained HTML design report", button: "Generate", defaultPath: "LibeRality-report.html", onClose: function () { modal[1](null); } }) : null);
  }
  function installModelBrowserHandler() {
    if (!window.Shiny || !window.Shiny.addCustomMessageHandler || window.__liberalityModelBrowserHandler) return;
    window.__liberalityModelBrowserHandler = true;
    window.Shiny.addCustomMessageHandler("liberality-model-browser", function (message) {
      window.dispatchEvent(new CustomEvent("liberality:model-browser", { detail: message || {} }));
    });
  }
  installModelBrowserHandler();
  document.addEventListener("shiny:connected", installModelBrowserHandler);
  window.LibeRalityWorkbench = App;
  reactR.reactWidget("liberalityWorkbench", "output", { LibeRalityWorkbench: App }, {});
})();
