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
  function Table(p) { var rows = list(p.rows); if (!rows.length) return e(Empty, { title: val(p.empty, "No results"), detail: "Run the corresponding analysis to populate this view." }); var cols = p.columns || Object.keys(rows[0]); return e("div", { className: "ly-table-wrap" }, e("table", { className: "ly-table" }, e("thead", null, e("tr", null, cols.map(function (c) { return e("th", { key: c.key || c }, c.label || c); }))), e("tbody", null, rows.map(function (r, i) { return e("tr", { key: i, className: p.onRowClick ? "ly-clickable-row" : "", tabIndex: p.onRowClick ? 0 : undefined, onClick: p.onRowClick ? function () { p.onRowClick(r); } : undefined, onKeyDown: p.onRowClick ? function (event) { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); p.onRowClick(r); } } : undefined }, cols.map(function (c) { var key = c.key || c, value = r[key]; if (c.format) value = c.format(value, r); return e("td", { key: key }, value === null || value === undefined ? "--" : String(value)); })); })))); }
  function csv(values, key) {
    return list(values).map(function (x) {
      return key ? val(x[key], "") : x;
    }).join(", ");
  }
  function useForm(initial) {
    var state = React.useState(initial);
    function set(name, value) {
      state[1](function (current) {
        var next = Object.assign({}, current);
        next[name] = value;
        return next;
      });
    }
    return [state[0], set];
  }
  function input(form, set, name, extra) {
    return Object.assign({
      value: val(form[name], ""),
      onChange: function (event) { set(name, event.target.value); }
    }, extra || {});
  }
  function DefinitionList(p) {
    var rows = list(p.rows);
    if (!rows.length) return e(Empty, {
      title: p.emptyTitle || "Nothing configured",
      detail: p.emptyDetail || "Add an item to complete this part of the design."
    });
    return e("div", { className: "ly-definition-list" }, rows.map(function (row) {
      return e("article", { className: "ly-definition-row", key: row.id },
        e("div", null, e("strong", null, row.name), e("span", null, p.detail(row))),
        e(Button, { className: "ly-quiet", onClick: function () { p.onEdit(row); } }, "Edit"));
    }));
  }
  function ConfirmModal(p) {
    var confirmation = React.useState("");
    return e(Modal, { title: p.title, subtitle: p.subtitle, onClose: p.onClose },
      e("div", { className: "ly-danger-callout" },
        e("strong", null, p.warning),
        e("p", null, p.detail || "This action cannot be undone.")),
      e(Field, { label: "Type YES to confirm" },
        e("input", { value: confirmation[0], autoFocus: true, onChange: function (x) { confirmation[1](x.target.value); } })),
      e("footer", { className: "ly-modal-actions" },
        e(Button, { onClick: p.onClose }, "Cancel"),
        e(Button, {
          className: "ly-danger",
          disabled: confirmation[0] !== "YES",
          onClick: function () { p.onConfirm(confirmation[0]); }
        }, p.button || "Confirm")));
  }
  function DesignIdentityModal(p) {
    var state = useForm({ name: p.design.name || "", description: p.design.description || "" });
    return e(Modal, { title: "Design details", subtitle: "Name and describe this versioned design", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Design name", className: "ly-span-2" }, e("input", input(state[0], state[1], "name"))),
        e(Field, { label: "Description", className: "ly-span-2" }, e("textarea", input(state[0], state[1], "description", { rows: 4 }))),
        e("footer", { className: "ly-modal-actions ly-span-2" },
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, {
            className: "ly-primary", disabled: !String(state[0].name).trim(),
            onClick: function () { emit(p.owner, "set_design_identity", state[0]); p.onClose(); }
          }, "Save details"))));
  }
  function ArmModal(p) {
    var arm = p.arm || null, doses = list(arm && arm.doses), first = doses[0] || {}, costs = (arm && arm.costs) || {};
    var state = useForm({
      id: arm ? arm.id : "", name: arm ? arm.name : "New arm",
      size: arm ? String(arm.size) : "20", allocation: arm ? String(arm.allocation) : "1",
      population: arm ? arm.population : "default",
      samplingTimes: arm ? csv(arm.samplingTimes) : "0.5, 1, 2, 4, 8, 12, 24",
      doseTimes: doses.length ? csv(doses, "TIME") : "0",
      doseAmounts: doses.length ? csv(doses, "AMT") : "100",
      rates: doses.length ? csv(doses, "RATE") : "0",
      route: arm ? val(arm.route, "extravascular") : "extravascular",
      doseCmt: arm ? String(val(arm.doseCmt, 1)) : "1",
      observationCmt: arm ? String(val(arm.observationCmt, 1)) : "1",
      dvid: arm ? String(val(arm.dvid, 1)) : "1",
      ii: arm ? String(val(arm.ii, 0)) : "0",
      addl: arm ? String(val(arm.addl, 0)) : "0",
      ss: arm ? String(val(arm.ss, 0)) : "0",
      sampleVolume: arm ? String(val(arm.sampleVolume, 0)) : "0",
      costFixed: String(val(costs.fixed, 0)), costSubject: String(val(costs.per_subject, 0)),
      costVisit: String(val(costs.per_visit, 0)), costSample: String(val(costs.per_sample, 0)),
      costAssay: String(val(costs.assay, 0))
    });
    var deleting = React.useState(false);
    if (deleting[0]) return e(ConfirmModal, {
      title: "Delete " + arm.name + "?", subtitle: "Remove this arm and its arm-specific variables",
      warning: "The design arm will be removed.", onClose: function () { deleting[1](false); },
      button: "Delete arm", onConfirm: function () {
        emit(p.owner, "arm_delete", { id: arm.id }); p.onClose();
      }
    });
    return e(Modal, {
      className: "ly-wide-modal", title: arm ? "Edit " + arm.name : "Add design arm",
      subtitle: "Exact allocation, dosing, observations, burden and cost", onClose: p.onClose
    }, e("div", { className: "ly-form-grid" },
      e(Field, { label: "Arm name" }, e("input", input(state[0], state[1], "name"))),
      e(Field, { label: "Population stratum" }, e("input", input(state[0], state[1], "population"))),
      e(Field, { label: "Subjects" }, e("input", input(state[0], state[1], "size", { type: "number", min: 0 }))),
      e(Field, { label: "Allocation weight" }, e("input", input(state[0], state[1], "allocation", { type: "number", min: 0, step: "any" }))),
      e(Field, { label: "Sampling times (hours)", className: "ly-span-2", help: "Comma-separated observation times." }, e("input", input(state[0], state[1], "samplingTimes"))),
      e(Field, { label: "Dose times (hours)", help: "Comma-separated administration times." }, e("input", input(state[0], state[1], "doseTimes"))),
      e(Field, { label: "Dose amounts", help: "One amount or one value per dose time." }, e("input", input(state[0], state[1], "doseAmounts"))),
      e(Field, { label: "Rates", help: "Zero is bolus/extravascular; otherwise amount/hour." }, e("input", input(state[0], state[1], "rates"))),
      e(Field, { label: "Route" }, e("select", input(state[0], state[1], "route"),
        ["extravascular", "oral", "intravenous", "subcutaneous", "intramuscular", "other"].map(function (x) { return e("option", { key: x, value: x }, x); }))),
      e("details", { className: "ly-details ly-span-2" }, e("summary", null, "Advanced schedule, cost and burden"),
        e("div", { className: "ly-form-grid" },
          e(Field, { label: "Dose compartment" }, e("input", input(state[0], state[1], "doseCmt", { type: "number", min: 1 }))),
          e(Field, { label: "Observation compartment" }, e("input", input(state[0], state[1], "observationCmt", { type: "number", min: 1 }))),
          e(Field, { label: "DVID" }, e("input", input(state[0], state[1], "dvid", { type: "number", min: 1 }))),
          e(Field, { label: "Repeat interval (II)" }, e("input", input(state[0], state[1], "ii", { type: "number", min: 0 }))),
          e(Field, { label: "Additional doses (ADDL)" }, e("input", input(state[0], state[1], "addl", { type: "number", min: 0 }))),
          e(Field, { label: "Steady-state flag" }, e("select", input(state[0], state[1], "ss"), e("option", { value: "0" }, "No"), e("option", { value: "1" }, "Yes"))),
          e(Field, { label: "Sample volume" }, e("input", input(state[0], state[1], "sampleVolume", { type: "number", min: 0, step: "any" }))),
          e("div", null),
          [["costFixed", "Fixed cost"], ["costSubject", "Cost per subject"], ["costVisit", "Cost per visit"], ["costSample", "Cost per sample"], ["costAssay", "Assay cost"]].map(function (entry) {
            return e(Field, { key: entry[0], label: entry[1] }, e("input", input(state[0], state[1], entry[0], { type: "number", min: 0, step: "any" })));
          }))),
      e("footer", { className: "ly-modal-actions ly-span-2" },
        arm ? e(Button, { className: "ly-danger-quiet ly-push-left", onClick: function () { deleting[1](true); } }, "Delete arm") : null,
        e(Button, { onClick: p.onClose }, "Cancel"),
        e(Button, {
          className: "ly-primary", disabled: !String(state[0].name).trim() || !String(state[0].samplingTimes).trim(),
          onClick: function () { emit(p.owner, "arm_save", state[0]); p.onClose(); }
        }, arm ? "Apply changes" : "Add arm"))));
  }
  function EndpointModal(p) {
    var item = p.item || null;
    var state = useForm({
      id: item ? item.id : "", name: item ? item.name : "New endpoint",
      type: item ? item.type : "continuous", dvid: item ? String(item.dvid) : "1",
      link: item ? item.link : "", scale: item ? item.scale : "linear_predictor",
      distribution: item ? item.distribution : "", thresholds: item ? csv(item.thresholds) : "",
      dispersion: item ? val(item.dispersion, "") : ""
    });
    var endpointOptions = (p.owner.endpointOptions || {})[state[0].type] || {
      links: ["identity"], distributions: ["normal"]
    };
    var availableLinks = list(endpointOptions.links);
    var availableDistributions = list(endpointOptions.distributions);
    var deleting = React.useState(false);
    if (deleting[0]) return e(ConfirmModal, {
      title: "Delete " + item.name + "?", subtitle: "Remove this outcome definition",
      warning: "The endpoint will be removed from the design.", onClose: function () { deleting[1](false); },
      button: "Delete endpoint", onConfirm: function () { emit(p.owner, "endpoint_delete", { id: item.id }); p.onClose(); }
    });
    return e(Modal, { title: item ? "Edit endpoint" : "Add endpoint", subtitle: "Statistical outcome definition", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Endpoint name", className: "ly-span-2" }, e("input", input(state[0], state[1], "name"))),
        e(Field, { label: "Outcome type" }, e("select", {
          value: state[0].type,
          onChange: function (event) {
            var type = event.target.value;
            var options = (p.owner.endpointOptions || {})[type] || {
              links: ["identity"], distributions: ["normal"]
            };
            state[1]("type", type);
            state[1]("link", list(options.links)[0] || "identity");
            state[1]("distribution", list(options.distributions)[0] || "normal");
          }
        },
          ["continuous", "binary", "ordinal", "count", "time_to_event", "recurrent_event"].map(function (x) { return e("option", { key: x, value: x }, x.replace(/_/g, " ")); }))),
        e(Field, { label: "DVID" }, e("input", input(state[0], state[1], "dvid", { type: "number", min: 1 }))),
        e(Field, { label: "Link" }, e("select", {
          value: availableLinks.indexOf(state[0].link) >= 0 ? state[0].link : availableLinks[0],
          onChange: function (event) { state[1]("link", event.target.value); }
        }, availableLinks.map(function (option) {
          return e("option", { key: option, value: option }, option.replace(/_/g, " "));
        }))),
        e(Field, { label: "Distribution" }, e("select", {
          value: availableDistributions.indexOf(state[0].distribution) >= 0 ? state[0].distribution : availableDistributions[0],
          onChange: function (event) { state[1]("distribution", event.target.value); }
        }, availableDistributions.map(function (option) {
          return e("option", { key: option, value: option }, option.replace(/_/g, " "));
        }))),
        e(Field, { label: "Prediction scale" }, e("select", input(state[0], state[1], "scale"),
          e("option", { value: "linear_predictor" }, "Linear predictor"), e("option", { value: "response" }, "Response scale"))),
        e(Field, { label: "Dispersion", help: "Optional count/Weibull parameter." }, e("input", input(state[0], state[1], "dispersion", { type: "number", min: 0, step: "any" }))),
        state[0].type === "ordinal" ? e(Field, { label: "Ordinal thresholds", className: "ly-span-2" }, e("input", input(state[0], state[1], "thresholds"))) : null,
        e("footer", { className: "ly-modal-actions ly-span-2" },
          item ? e(Button, { className: "ly-danger-quiet ly-push-left", onClick: function () { deleting[1](true); } }, "Delete endpoint") : null,
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, { className: "ly-primary", disabled: !String(state[0].name).trim(), onClick: function () { emit(p.owner, "endpoint_save", state[0]); p.onClose(); } }, "Save endpoint"))));
  }
  function ScenarioModal(p) {
    var item = p.item || null;
    var state = useForm({
      id: item ? item.id : "", name: item ? item.name : "New scenario",
      probability: item ? String(item.probability) : "0.1",
      adherence: item ? String(item.adherence) : "1",
      dropout: item ? String(item.dropout) : "0",
      missedSample: item ? String(item.missedSample) : "0",
      theta: item ? csv(item.theta) : "", omega: item ? csv(item.omega) : "", sigma: item ? csv(item.sigma) : ""
    });
    var deleting = React.useState(false);
    if (deleting[0]) return e(ConfirmModal, {
      title: "Delete " + item.name + "?", subtitle: "Remove this uncertainty scenario",
      warning: "Scenario probabilities will be renormalised.", onClose: function () { deleting[1](false); },
      button: "Delete scenario", onConfirm: function () { emit(p.owner, "scenario_delete", { id: item.id }); p.onClose(); }
    });
    return e(Modal, { title: item ? "Edit scenario" : "Add scenario", subtitle: "Parameter and operational uncertainty", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Scenario name", className: "ly-span-2" }, e("input", input(state[0], state[1], "name"))),
        e(Field, { label: "Relative weight" }, e("input", input(state[0], state[1], "probability", { type: "number", min: 0, max: 1, step: "any" }))),
        e(Field, { label: "Adherence probability" }, e("input", input(state[0], state[1], "adherence", { type: "number", min: 0, max: 1, step: "any" }))),
        e(Field, { label: "Dropout probability" }, e("input", input(state[0], state[1], "dropout", { type: "number", min: 0, max: 1, step: "any" }))),
        e(Field, { label: "Missed-sample probability" }, e("input", input(state[0], state[1], "missedSample", { type: "number", min: 0, max: 1, step: "any" }))),
        e(Field, { label: "THETA overrides", className: "ly-span-2", help: "Optional comma-separated vector; blank uses nominal values." }, e("input", input(state[0], state[1], "theta"))),
        e(Field, { label: "OMEGA overrides", className: "ly-span-2" }, e("input", input(state[0], state[1], "omega"))),
        e(Field, { label: "SIGMA overrides", className: "ly-span-2" }, e("input", input(state[0], state[1], "sigma"))),
        e("footer", { className: "ly-modal-actions ly-span-2" },
          item ? e(Button, { className: "ly-danger-quiet ly-push-left", onClick: function () { deleting[1](true); } }, "Delete scenario") : null,
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, { className: "ly-primary", disabled: !String(state[0].name).trim(), onClick: function () { emit(p.owner, "scenario_save", state[0]); p.onClose(); } }, "Save scenario"))));
  }
  function VariableModal(p) {
    var item = p.item || null, arms = list(p.owner.arms);
    var state = useForm({
      id: item ? item.id : "", name: item ? item.name : "New design variable",
      target: item ? item.target : "sampling_time", arm: item ? item.arm : (arms[0] ? arms[0].id : ""),
      index: item ? String(item.index) : "1", lower: item ? String(item.lower) : "0",
      upper: item ? String(item.upper) : "24", type: item ? item.type : "continuous",
      values: item ? csv(item.values) : "", covariate: item ? val(item.covariate, "") : ""
    });
    var deleting = React.useState(false);
    if (deleting[0]) return e(ConfirmModal, {
      title: "Delete " + item.name + "?", subtitle: "Remove this optimisation variable",
      warning: "Future optimisations will no longer change this quantity.", onClose: function () { deleting[1](false); },
      button: "Delete variable", onConfirm: function () { emit(p.owner, "variable_delete", { id: item.id }); p.onClose(); }
    });
    return e(Modal, { title: item ? "Edit design variable" : "Add design variable", subtitle: "Quantity and permitted design space", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Variable name", className: "ly-span-2" }, e("input", input(state[0], state[1], "name"))),
        e(Field, { label: "Target" }, e("select", input(state[0], state[1], "target"),
          ["sampling_time", "dose", "rate", "duration", "arm_size", "allocation", "covariate"].map(function (x) { return e("option", { key: x, value: x }, x.replace(/_/g, " ")); }))),
        e(Field, { label: "Arm" }, e("select", input(state[0], state[1], "arm"), arms.map(function (x) { return e("option", { key: x.id, value: x.id }, x.name); }))),
        e(Field, { label: "Observation/dose index" }, e("input", input(state[0], state[1], "index", { type: "number", min: 1 }))),
        e(Field, { label: "Variable type" }, e("select", input(state[0], state[1], "type"),
          ["continuous", "integer", "discrete", "categorical"].map(function (x) { return e("option", { key: x, value: x }, x); }))),
        e(Field, { label: "Lower bound" }, e("input", input(state[0], state[1], "lower", { type: "number", step: "any" }))),
        e(Field, { label: "Upper bound" }, e("input", input(state[0], state[1], "upper", { type: "number", step: "any" }))),
        state[0].type === "discrete" || state[0].type === "categorical" ? e(Field, { label: "Candidate values", className: "ly-span-2" }, e("input", input(state[0], state[1], "values"))) : null,
        state[0].target === "covariate" ? e(Field, { label: "Covariate column", className: "ly-span-2" }, e("input", input(state[0], state[1], "covariate"))) : null,
        e("footer", { className: "ly-modal-actions ly-span-2" },
          item ? e(Button, { className: "ly-danger-quiet ly-push-left", onClick: function () { deleting[1](true); } }, "Delete variable") : null,
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, { className: "ly-primary", disabled: !String(state[0].name).trim(), onClick: function () { emit(p.owner, "variable_save", state[0]); p.onClose(); } }, "Save variable"))));
  }
  function ConstraintModal(p) {
    var item = p.item || null, arms = list(p.owner.arms), endpoints = list(p.owner.endpoints);
    var state = useForm({
      id: item ? item.id : "", name: item ? item.name : "New constraint",
      type: item ? item.type : "total_subjects", limit: item ? String(item.limit) : "100",
      arm: item ? val(item.arm, "") : "", endpoint: item ? val(item.endpoint, "") : "",
      parameters: item ? csv(item.parameters) : "", lower: item ? val(item.lower, "") : "",
      upper: item ? val(item.upper, "") : ""
    });
    var deleting = React.useState(false);
    if (item && item.scripted) return e(Modal, { title: item.name, subtitle: "Scripted custom constraint", onClose: p.onClose },
      e("div", { className: "ly-callout ly-callout-warning" }, "Custom R-function constraints remain read-only in the GUI because executable functions cannot be represented in a portable typed design contract."),
      e("footer", { className: "ly-modal-actions" }, e(Button, { onClick: p.onClose }, "Close")));
    if (deleting[0]) return e(ConfirmModal, {
      title: "Delete " + item.name + "?", subtitle: "Remove this feasibility rule",
      warning: "The constraint will no longer be enforced.", onClose: function () { deleting[1](false); },
      button: "Delete constraint", onConfirm: function () { emit(p.owner, "constraint_delete", { id: item.id }); p.onClose(); }
    });
    return e(Modal, { title: item ? "Edit constraint" : "Add constraint", subtitle: "Operational, resource or statistical feasibility", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Constraint name", className: "ly-span-2" }, e("input", input(state[0], state[1], "name"))),
        e(Field, { label: "Constraint type" }, e("select", input(state[0], state[1], "type"),
          ["min_separation", "max_samples", "total_subjects", "total_cost", "max_blood_volume", "max_duration", "arm_size", "allocation", "max_rse", "minimum_power", "exposure"].map(function (x) { return e("option", { key: x, value: x }, x.replace(/_/g, " ")); }))),
        e(Field, { label: "Limit" }, e("input", input(state[0], state[1], "limit", { type: "number", step: "any" }))),
        e(Field, { label: "Arm (optional)" }, e("select", input(state[0], state[1], "arm"), e("option", { value: "" }, "All arms"), arms.map(function (x) { return e("option", { key: x.id, value: x.id }, x.name); }))),
        e(Field, { label: "Endpoint (optional)" }, e("select", input(state[0], state[1], "endpoint"), e("option", { value: "" }, "All endpoints"), endpoints.map(function (x) { return e("option", { key: x.id, value: x.id }, x.name); }))),
        e(Field, { label: "Parameters (optional)", className: "ly-span-2", help: "Comma-separated parameter names for precision constraints." }, e("input", input(state[0], state[1], "parameters"))),
        e(Field, { label: "Lower interval bound (optional)" }, e("input", input(state[0], state[1], "lower", { type: "number", step: "any" }))),
        e(Field, { label: "Upper interval bound (optional)" }, e("input", input(state[0], state[1], "upper", { type: "number", step: "any" }))),
        e("footer", { className: "ly-modal-actions ly-span-2" },
          item ? e(Button, { className: "ly-danger-quiet ly-push-left", onClick: function () { deleting[1](true); } }, "Delete constraint") : null,
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, { className: "ly-primary", disabled: !String(state[0].name).trim(), onClick: function () { emit(p.owner, "constraint_save", state[0]); p.onClose(); } }, "Save constraint"))));
  }
  function CriterionHelpModal(p) {
    var item = p.item || {};
    function section(title, text) { return e("section", { className: "ly-help-section" }, e("h3", null, title), e("p", null, text)); }
    return e(Modal, { className: "ly-criterion-modal", title: val(item.label, item.type), subtitle: val(item.summary, "Optimal-design criterion"), onClose: p.onClose },
      e("div", { className: "ly-criterion-header" }, e(Badge, { tone: "accent" }, item.group), e(Badge, null, item.direction)),
      section("How it is constructed", item.construction),
      e("div", { className: "ly-two" }, section("Strengths", item.strengths), section("Weaknesses", item.limitations)),
      section("Typical use cases", item.useCases),
      section("What it needs", item.requirements),
      e("div", { className: "ly-callout" }, "LibeRality evaluates the criterion under the declared model, parameter values, scenarios and constraints. A statistically optimal design can still be operationally or clinically unsuitable, so inspect all diagnostics and assumptions."),
      e("footer", { className: "ly-modal-actions" }, e(Button, { className: "ly-primary", onClick: p.onClose }, "Close")));
  }
  function OptimiseModal(p) {
    var method = React.useState("auto");
    var maxit = React.useState("40");
    var labels = {
      auto: "Automatic selection — recommended", "L-BFGS-B": "Gradient optimisation (L-BFGS-B)",
      "Nelder-Mead": "Derivative-free simplex (Nelder–Mead)", pso: "Particle swarm",
      coordinate_exchange: "Coordinate exchange", hybrid: "Hybrid continuous/discrete",
      multiplicative: "Multiplicative approximate-design update", fedorov_wynn: "Fedorov–Wynn exchange"
    };
    return e(Modal, { title: "Optimise design", subtitle: "Continuous, discrete, integer, and hybrid variables", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Algorithm" }, e("select", { value: method[0], onChange: function (x) { method[1](x.target.value); } }, Object.keys(labels).map(function (x) { return e("option", { key: x, value: x }, labels[x]); }))),
        e(Field, { label: "Maximum iterations" }, e("input", { type: "number", min: 1, value: maxit[0], onChange: function (x) { maxit[1](x.target.value); } })),
        e("div", { className: "ly-run-summary ly-span-2" },
          e("strong", null, list(p.owner.variables).length + " optimisable variables"),
          e("span", null, list(p.owner.constraintDefinitions).length + " constraints · " + list(p.owner.scenarios).length + " scenarios · " + val(p.owner.criterion && p.owner.criterion.guidance && p.owner.criterion.guidance.label, p.owner.criterion.type))),
        e("div", { className: "ly-callout ly-span-2" }, "Automatic selection chooses an algorithm from the declared variable types. The selected criterion, constraints and scenarios are retained in the reproducible run record."),
        e("footer", { className: "ly-modal-actions ly-span-2" },
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, { className: "ly-primary", disabled: !list(p.owner.variables).length && method[0] !== "multiplicative" && method[0] !== "fedorov_wynn", onClick: function () { emit(p.owner, "optimise", { method: method[0], maxit: maxit[0] }); p.onClose(); } }, "Start optimisation"))));
  }
  function SimulateModal(p) {
    var n = React.useState("20");
    var fit = React.useState(false);
    var method = React.useState("FOCEI");
    var seed = React.useState("7301");
    return e(Modal, { title: "Simulate complete trials", subtitle: "Empirical operating-characteristic assessment", onClose: p.onClose },
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Replicated trials" }, e("input", { type: "number", min: 1, value: n[0], onChange: function (x) { n[1](x.target.value); } })),
        e(Field, { label: "Analysis method" }, e("select", { value: method[0], disabled: !fit[0], onChange: function (x) { method[1](x.target.value); } }, ["FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "IMP", "SAEM", "BAYES"].map(function (x) { return e("option", { key: x }, x); }))),
        e(Field, { label: "Random seed" }, e("input", { type: "number", value: seed[0], onChange: function (x) { seed[1](x.target.value); } })),
        e("div", null),
        e("label", { className: "ly-check ly-span-2" }, e("input", { type: "checkbox", checked: fit[0], onChange: function (x) { fit[1](x.target.checked); } }), e("span", null, "Refit every simulated trial (substantially slower)")),
        e("div", { className: "ly-callout ly-span-2" }, fit[0] ? "Each simulated dataset will be re-estimated. Runtime is approximately the number of trials multiplied by one model fit." : "Simulation-only mode checks predicted operating characteristics without re-estimating every trial."),
        e("footer", { className: "ly-modal-actions ly-span-2" },
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, { className: "ly-primary", onClick: function () { emit(p.owner, "simulate", { n: n[0], fit: fit[0], method: method[0], seed: seed[0] }); p.onClose(); } }, "Run simulations"))));
  }
  function FileModal(p) {
    var path = React.useState(p.defaultPath || "LibeRality-design.rds");
    return e(Modal, { title: p.title, subtitle: p.subtitle, onClose: p.onClose },
      p.owner.hosted ? e("div", { className: "ly-callout ly-callout-warning" }, "This deployment runs on a server. The path below belongs to the server, not your computer. Browser upload/download support should be configured by the deployment administrator.") : null,
      e(Field, { label: p.owner.hosted ? "Server path" : "Local path", help: "The R process must have access to this path." }, e("input", { value: path[0], autoFocus: true, onChange: function (x) { path[1](x.target.value); } })),
      e("footer", { className: "ly-modal-actions" }, e(Button, { onClick: p.onClose }, "Cancel"), e(Button, { className: "ly-primary", onClick: function () { emit(p.owner, p.action, { path: path[0] }); p.onClose(); } }, p.button)));
  }
  function SchedulePlot(p) { var arms = list(p.arms); if (!arms.length) return null; var all = [].concat.apply([], arms.map(function (a) { return list(a.samplingTimes).concat(list(a.doses).map(function (d) { return Number(d.TIME); })); })).filter(isFinite); var min = Math.min.apply(null, all.concat([0])), max = Math.max.apply(null, all.concat([1])); if (max <= min) max = min + 1; function x(t) { return 145 + (Number(t) - min) / (max - min) * 720; } var height = 70 + arms.length * 72; return e("div", { className: "ly-chart" }, e("svg", { viewBox: "0 0 920 " + height, role: "img", "aria-label": "Study arm schedule" }, arms.map(function (arm, i) { var y = 55 + i * 72; return e("g", { key: arm.id }, e("text", { x: 15, y: y + 5, className: "ly-chart-name" }, arm.name), e("line", { x1: 145, y1: y, x2: 865, y2: y, className: "ly-axis" }), list(arm.doses).map(function (d, j) { return e("g", { key: "d" + j }, e("line", { x1: x(d.TIME), y1: y - 22, x2: x(d.TIME), y2: y + 22, className: "ly-dose" }), e("text", { x: x(d.TIME) + 4, y: y - 25, className: "ly-chart-label" }, fmt(d.AMT, 0))); }), list(arm.samplingTimes).map(function (t, j) { return e("circle", { key: "s" + j, cx: x(t), cy: y, r: 6, className: "ly-sample" }); })); }), e("text", { x: 145, y: height - 5, className: "ly-chart-label" }, fmt(min, 1) + " h"), e("text", { x: 840, y: height - 5, className: "ly-chart-label" }, fmt(max, 1) + " h"))); }
  function BarChart(p) { var rows = list(p.rows).filter(function (r) { return num(r[p.valueKey]) !== null; }); if (!rows.length) return e(Empty, { title: "No precision results", detail: "Evaluate the design first." }); var max = Math.max.apply(null, rows.map(function (r) { return Math.abs(Number(r[p.valueKey])); }).concat([1])); return e("div", { className: "ly-bars" }, rows.map(function (r) { var width = Math.min(100, Math.abs(Number(r[p.valueKey])) / max * 100); return e("div", { className: "ly-bar-row", key: r.parameter || r.name }, e("span", null, r.parameter || r.name), e("div", null, e("i", { style: { width: width + "%" } })), e("strong", null, fmt(r[p.valueKey], 2) + val(p.suffix, ""))); })); }
  function TracePlot(p) { var rows = list(p.rows).filter(function (r) { return num(r.criterion) !== null; }); if (!rows.length) return e(Empty, { title: "No optimisation trace", detail: "Run an optimisation to inspect convergence." }); var vals = rows.map(function (r) { return Number(r.criterion); }), min = Math.min.apply(null, vals), max = Math.max.apply(null, vals); if (max === min) max = min + 1; function x(i) { return 50 + i / Math.max(1, rows.length - 1) * 810; } function y(v) { return 220 - (v - min) / (max - min) * 165; } var path = vals.map(function (v, i) { return (i ? "L" : "M") + x(i) + " " + y(v); }).join(" "); return e("div", { className: "ly-chart" }, e("svg", { viewBox: "0 0 900 260" }, e("line", { x1: 50, y1: 220, x2: 860, y2: 220, className: "ly-axis" }), e("path", { d: path, className: "ly-trace" }), e("text", { x: 55, y: 42, className: "ly-chart-label" }, fmt(max, 3)), e("text", { x: 55, y: 238, className: "ly-chart-label" }, fmt(min, 3)))); }
  function EndpointSimulationPlot(p) {
    var rows = list(p.rows).filter(function (r) { return num(r.time) !== null && num(r.median) !== null; });
    if (!rows.length) return e(Empty, { title: "No endpoint curve", detail: "No finite continuous endpoint simulations are available." });
    var times = rows.map(function (r) { return Number(r.time); });
    var values = [].concat.apply([], rows.map(function (r) { return [num(r.lower), num(r.upper), num(r.median)]; })).filter(function (x) { return x !== null; });
    var minX = Math.min.apply(null, times), maxX = Math.max.apply(null, times), minY = Math.min.apply(null, values), maxY = Math.max.apply(null, values);
    if (maxX <= minX) maxX = minX + 1; if (maxY <= minY) maxY = minY + 1;
    function x(value) { return 60 + (Number(value) - minX) / (maxX - minX) * 780; }
    function y(value) { return 225 - (Number(value) - minY) / (maxY - minY) * 175; }
    var arms = Array.from(new Set(rows.map(function (r) { return r.arm; })));
    var colours = ["#B87333", "#397C83", "#7D6A91", "#71825B", "#B45F5F"];
    return e("div", { className: "ly-chart ly-endpoint-chart" },
      e("svg", { viewBox: "0 0 900 270", role: "img", "aria-label": "Simulated endpoint profile" },
        e("line", { x1: 60, y1: 225, x2: 840, y2: 225, className: "ly-axis" }),
        e("line", { x1: 60, y1: 50, x2: 60, y2: 225, className: "ly-axis" }),
        arms.map(function (arm, index) {
          var data = rows.filter(function (r) { return r.arm === arm; }).sort(function (a, b) { return Number(a.time) - Number(b.time); });
          var upper = data.map(function (r) { return x(r.time) + "," + y(r.upper); });
          var lower = data.slice().reverse().map(function (r) { return x(r.time) + "," + y(r.lower); });
          var median = data.map(function (r, i) { return (i ? "L" : "M") + x(r.time) + " " + y(r.median); }).join(" ");
          return e("g", { key: arm }, e("polygon", { points: upper.concat(lower).join(" "), fill: colours[index % colours.length], opacity: 0.14 }), e("path", { d: median, fill: "none", stroke: colours[index % colours.length], strokeWidth: 3 }), e("text", { x: 690, y: 24 + index * 17, fill: colours[index % colours.length], className: "ly-chart-label" }, arm));
        }),
        e("text", { x: 60, y: 247, className: "ly-chart-label" }, fmt(minX, 2) + " h"),
        e("text", { x: 810, y: 247, className: "ly-chart-label" }, fmt(maxX, 2) + " h"),
        e("text", { x: 8, y: 55, className: "ly-chart-label" }, fmt(maxY, 3)),
        e("text", { x: 8, y: 225, className: "ly-chart-label" }, fmt(minY, 3))));
  }
  function ConstraintDetailsModal(p) {
    var rows = list(p.rows), selected = p.selected;
    if (selected) rows = rows.filter(function (x) { return x.id === selected.id; });
    var violated = rows.filter(function (x) { return !x.feasible; });
    if (!selected && violated.length) rows = violated;
    return e(Modal, { title: violated.length ? "Feasibility constraints" : "Constraint evaluation", subtitle: violated.length ? violated.length + " violated constraint(s)" : "All evaluated constraints are feasible", onClose: p.onClose, className: "ly-modal-wide" },
      rows.length ? e("div", { className: "ly-constraint-details" }, rows.map(function (row) { return e("article", { key: row.id || row.name, className: row.feasible ? "feasible" : "violated" }, e("header", null, e("strong", null, row.name), e(Badge, { tone: row.feasible ? "success" : "warning" }, row.feasible ? "Feasible" : "Violated")), e("p", null, row.rule), e("p", null, row.detail), e("dl", null, e("div", null, e("dt", null, "Evaluated"), e("dd", null, fmt(row.value, 5))), e("div", null, e("dt", null, "Limit"), e("dd", null, fmt(row.limit, 5))), e("div", null, e("dt", null, "Type"), e("dd", null, String(row.type).replace(/_/g, " "))))); })) : e(Empty, { title: "No constraints configured", detail: "Add feasibility constraints under Objectives." }));
  }
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
  function ModelParameterEditor(p) {
    function update(index, field, value) {
      p.setRows(function (current) {
        return current.map(function (row, position) {
          if (position !== index) return row;
          var next = Object.assign({}, row);
          next[field] = value;
          return next;
        });
      });
    }
    return e("div", { className: "ly-parameter-editor" },
      e("header", null,
        e("div", null, e("strong", null, p.title), e("span", null, p.help)),
        e(Button, {
          className: "ly-quiet", onClick: function () {
            p.setRows(function (current) {
              var index = current.length + 1;
              return current.concat([p.create(index, current)]);
            });
          }
        }, "+ Add")),
      p.rows.length ? e("div", { className: "ly-table-wrap" },
        e("table", { className: "ly-table ly-edit-table" },
          e("thead", null, e("tr", null,
            p.columns.map(function (column) {
              return e("th", { key: column.key }, column.label);
            }),
            e("th", null, "Fixed"), e("th", null, ""))),
          e("tbody", null, p.rows.map(function (row, index) {
            return e("tr", { key: index },
              p.columns.map(function (column) {
                return e("td", { key: column.key }, e("input", {
                  type: "number", step: "any", value: val(row[column.key], ""),
                  onChange: function (event) {
                    update(index, column.key, event.target.value);
                  }
                }));
              }),
              e("td", null, e("input", {
                type: "checkbox", checked: !!row.fixed,
                onChange: function (event) {
                  update(index, "fixed", event.target.checked);
                }
              })),
              e("td", null, e(Button, {
                className: "ly-danger-quiet ly-parameter-remove",
                title: "Remove parameter",
                onClick: function () {
                  p.setRows(function (current) {
                    return current.filter(function (_, position) {
                      return position !== index;
                    });
                  });
                }
              }, "Remove")));
          })))) : e("p", { className: "ly-muted" }, "No parameters declared."));
  }
  function ModelEditorModal(p) {
    var editor = p.model.editor || {}, parameters = list(editor.parameters);
    var form = useForm({
      name: val(editor.name, p.model.name),
      pk: val(editor.pk, ""),
      pred: val(editor.pred, ""),
      des: val(editor.des, ""),
      error: val(editor.error, "")
    });
    var theta = React.useState(parameters.filter(function (row) {
      return row.type === "THETA";
    }).map(function (row) { return Object.assign({}, row); }));
    var omega = React.useState(parameters.filter(function (row) {
      return row.type === "OMEGA";
    }).map(function (row) { return Object.assign({}, row); }));
    var sigma = React.useState(parameters.filter(function (row) {
      return row.type === "SIGMA";
    }).map(function (row) { return Object.assign({}, row); }));
    var mode = val(editor.predMode, "pk");
    function code(label, name, help, disabled) {
      return e(Field, { label: label, help: help, className: "ly-span-2" },
        e("textarea", input(form[0], form[1], name, {
          rows: name === "error" ? 6 : 9,
          className: "ly-code-editor", disabled: !!disabled
        })));
    }
    return e(Modal, {
      className: "ly-model-editor-modal",
      title: "Edit model definition",
      subtitle: val(p.model.typeLabel, "Validated LibeRation model"),
      onClose: p.onClose
    }, e("div", { className: "ly-stack" },
      e("div", { className: "ly-callout" },
        "Apply changes recompiles and validates the model through LibeRation. Invalid code, parameter references, bounds, or covariance structures are rejected before this design changes."),
      e("div", { className: "ly-form-grid" },
        e(Field, { label: "Model name", className: "ly-span-2" },
          e("input", input(form[0], form[1], "name"))),
        mode !== "pred" ? code("$PK", "pk", "ADVAN/PREDPP parameter and scaling assignments.") : null,
        mode === "pred" || mode === "pk_pred" ? code(
          mode === "pred" ? "$PRED" : "Post-ADVAN $PRED",
          "pred",
          mode === "pred" ? "Direct row-wise prediction code assigning F." : "Prediction layer reading F_ADVAN and assigning F."
        ) : null,
        mode !== "pred" && (String(form[0].des).trim() || [6, 8, 9, 10, 13, 14].indexOf(Number(p.model.advan)) >= 0) ?
          code("$DES", "des", "Differential-equation source where required by the structural route.") : null,
        code("$ERROR", "error",
          editor.errorEditable === false ? "Generated from the declared outcome model and intentionally read-only." : "Residual-error or likelihood assignments.",
          editor.errorEditable === false)),
      e(ModelParameterEditor, {
        title: "THETA", help: "Initial values and estimation bounds",
        rows: theta[0], setRows: theta[1],
        columns: [
          { key: "value", label: "Initial" },
          { key: "lower", label: "Lower" },
          { key: "upper", label: "Upper" }
        ],
        create: function () {
          return { value: 1, lower: 0.001, upper: 1000, fixed: false };
        }
      }),
      e(ModelParameterEditor, {
        title: "OMEGA", help: "Random-effect variance/covariance lower triangle",
        rows: omega[0], setRows: omega[1],
        columns: [
          { key: "row", label: "Row" },
          { key: "col", label: "Column" },
          { key: "value", label: "Initial" }
        ],
        create: function (index, current) {
          var dimension = current.reduce(function (maximum, row) {
            return Math.max(maximum, Number(row.row) || 0, Number(row.col) || 0);
          }, 0) + 1;
          return { row: dimension, col: dimension, value: 0.1, fixed: false };
        }
      }),
      e(ModelParameterEditor, {
        title: "SIGMA", help: "Residual-error parameters",
        rows: sigma[0], setRows: sigma[1],
        columns: [{ key: "value", label: "Initial" }],
        create: function () {
          return { value: 0.1, fixed: false };
        }
      }),
      e("footer", { className: "ly-modal-actions" },
        e(Button, { onClick: p.onClose }, "Cancel"),
        e(Button, {
          className: "ly-primary",
          disabled: !String(form[0].name).trim() || !theta[0].length,
          onClick: function () {
            emit(p.owner, "model_edit", Object.assign({}, form[0], {
              theta: theta[0], omega: omega[0], sigma: sigma[0],
              errorEditable: editor.errorEditable !== false
            }));
            p.onClose();
          }
        }, "Validate and apply"))));
  }
  function ModelSummary(p) {
    var model = p.model || {};
    var chooser = React.useState(false);
    var editor = React.useState(false);
    React.useEffect(function () { if (p.browser && p.browser.applied) chooser[1](false); },
      [p.browser && p.browser.applied]);
    return e("div", { className: "ly-model-summary" },
      e("div", { className: "ly-model-headline" },
        e("div", null, e("small", null, val(model.source, "Model")), e("h3", null, val(model.name, "Unnamed model")), e("p", null, val(model.family, ""))),
        e("div", null, e(Badge, { tone: "accent" }, val(model.typeLabel, "ADVAN" + val(model.advan, "-") + " / TRANS" + val(model.trans, "-"))), e(Badge, null, val(model.parameterSource, "parameter values")),
          p.editable ? e(Button, { className: "ly-primary", onClick: function () { editor[1](true); } }, "Edit model") : null,
          p.browser ? e(Button, { className: "ly-primary", onClick: function () { chooser[1](true); } }, "Change model") : null)),
      e(ModelDiagram, { diagram: model.diagram }),
      editor[0] && p.editable ? e(ModelEditorModal, { owner: p.owner, model: model, onClose: function () { editor[1](false); } }) : null,
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
                  record.typeLabel ? e("em", null, record.typeLabel) :
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
  function LegacyApp(props) {
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
          e(ModelSummary, { model: props.model, owner: props, browser: modelBrowser[0], editable: true })),
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
  function CriterionPicker(p) {
    var items = list(p.owner.criterionGuidance), current = p.owner.criterion && p.owner.criterion.guidance;
    var groups = [];
    items.forEach(function (item) {
      var group = groups.filter(function (entry) { return entry.name === item.group; })[0];
      if (!group) { group = { name: item.group, items: [] }; groups.push(group); }
      group.items.push(item);
    });
    return e("div", { className: "ly-criterion-picker" },
      e("div", { className: "ly-criterion-label" },
        e("label", null, "Design criterion"),
        e(Button, { className: "ly-help-button", title: "Explain this criterion", onClick: function () { p.open({ type: "criterion-help", item: current }); } }, "?")),
      e("select", {
        value: p.owner.criterion && p.owner.criterion.type,
        onChange: function (x) { emit(p.owner, "set_criterion", { type: x.target.value }); }
      }, groups.map(function (group) {
        return e("optgroup", { key: group.name, label: group.name }, group.items.map(function (item) {
          return e("option", { key: item.type, value: item.type }, item.label);
        }));
      })),
      current ? e("p", null, current.summary) : null);
  }
  function DesignWizardModal(p) {
    var templates = list(p.owner.designTemplates);
    var selected = React.useState(templates[0] ? templates[0].template : "");
    var step = React.useState(1);
    var current = templates.filter(function (item) {
      return item.template === selected[0];
    })[0] || templates[0];
    var settings = useForm({
      name: current ? current.name : "",
      baseDose: current ? String(current.default_dose) : "100",
      subjectsPerArm: current ? String(current.default_subjects_per_arm) : "20"
    });
    function choose(item) {
      selected[1](item.template);
      settings[1]("name", item.name);
      settings[1]("baseDose", String(item.default_dose));
      settings[1]("subjectsPerArm", String(item.default_subjects_per_arm));
    }
    if (!templates.length) return e(Modal, {
      title: "Trial design wizard", onClose: p.onClose
    }, e(Empty, {
      title: "No design templates available",
      detail: "The current LibeRality installation did not provide its template catalogue."
    }));
    return e(Modal, {
      className: "ly-wizard-modal", title: "Trial design wizard",
      subtitle: step[0] === 1 ? "Choose a clinically recognisable starting layout" : "Configure the generated design",
      onClose: p.onClose
    }, step[0] === 1 ? e("div", { className: "ly-stack" },
      e("p", { className: "ly-muted" },
        "Each template creates the ordinary versioned LibeRality design object. The current model and endpoints are retained, and every generated arm remains editable."),
      e("div", { className: "ly-template-grid" }, templates.map(function (item) {
        return e("button", {
          type: "button", key: item.template,
          className: "ly-template-card " + (selected[0] === item.template ? "active" : ""),
          onClick: function () { choose(item); }
        }, e("div", { className: "ly-template-meta" },
            e("small", null, item.category),
            item.regulatory ? e(Badge, { tone: "accent" }, "Regulatory-informed") : null),
          e("strong", null, item.name),
          e("p", null, item.summary),
          e("span", null, item.arms + (item.arms === 1 ? " arm" : " arms")));
      })),
      e("footer", { className: "ly-modal-actions" },
        e(Button, { onClick: p.onClose }, "Cancel"),
        e(Button, {
          className: "ly-primary", disabled: !selected[0],
          onClick: function () { step[1](2); }
        }, "Next"))) :
      e("div", { className: "ly-stack" },
        e("div", { className: "ly-wizard-selection" },
          e("small", null, current.category),
          e("strong", null, current.name),
          e("p", null, current.summary),
          current.framework ? e("span", null, current.framework) : null),
        e("div", { className: "ly-form-grid" },
          e(Field, { label: "Design name", className: "ly-span-2" },
            e("input", input(settings[0], settings[1], "name"))),
          e(Field, {
            label: "Reference dose",
            help: "Template dose levels are multiples of this value."
          }, e("input", input(settings[0], settings[1], "baseDose", {
            type: "number", min: 0, step: "any"
          }))),
          e(Field, {
            label: "Subjects per arm",
            help: current.arms + (current.arms === 1 ? " generated arm." : " generated arms.")
          }, e("input", input(settings[0], settings[1], "subjectsPerArm", {
            type: "number", min: 1, step: 1
          })))),
        e("div", { className: "ly-callout" },
          "Loading the template replaces the current arms, design variables, and constraints. It retains the current model, endpoints, population, uncertainty scenarios, provenance, and an audit entry for the prior design."),
        current.caution ? e("div", { className: "ly-callout ly-callout-warning" },
          e("strong", null, "Regulatory starting point"), e("br"),
          current.caution) : null,
        e("footer", { className: "ly-modal-actions" },
          e(Button, { className: "ly-push-left", onClick: function () { step[1](1); } }, "Back"),
          e(Button, { onClick: p.onClose }, "Cancel"),
          e(Button, {
            className: "ly-primary",
            disabled: !String(settings[0].name).trim() ||
              Number(settings[0].baseDose) < 0 ||
              Number(settings[0].subjectsPerArm) < 1,
            onClick: function () {
              emit(p.owner, "wizard_apply", Object.assign(
                { template: selected[0] }, settings[0]
              ));
              p.onClose();
            }
          }, "Load editable design"))));
  }
  function SaveDesignVersionModal(p) {
    var history = p.owner.designHistory || {};
    var current = list(history.records).filter(function (record) {
      return record.series_id === history.currentSeries;
    })[0];
    var hasSeries = !!history.currentSeries;
    var state = useForm({
      seriesName: current ? current.series_name : val((p.owner.design || {}).name, "Untitled design"),
      label: "",
      newSeries: !hasSeries
    });
    return e(Modal, {
      title: "Save design version",
      subtitle: hasSeries ? "Create an immutable version in the current design history" : "Start a reusable design history",
      onClose: p.onClose
    }, e("div", { className: "ly-form-grid" },
      e(Field, { className: "ly-span-2", label: "Design name" },
        e("input", input(state[0], state[1], "seriesName"))),
      e(Field, {
        className: "ly-span-2", label: "Version label",
        help: "Leave blank to use the next sequential label, such as Version 002."
      }, e("input", input(state[0], state[1], "label", {
        placeholder: "Optional label"
      }))),
      hasSeries ? e("label", { className: "ly-check ly-span-2" },
        e("input", {
          type: "checkbox", checked: !!state[0].newSeries,
          onChange: function (event) { state[1]("newSeries", event.target.checked); }
        }), e("span", null, "Start a new design rather than adding a version to the current design")) : null,
      e("div", { className: "ly-callout ly-span-2" },
        "Saved versions are immutable. Further edits remain in the active working copy until another version is saved."),
      e("footer", { className: "ly-modal-actions ly-span-2" },
        e(Button, { onClick: p.onClose }, "Cancel"),
        e(Button, {
          className: "ly-primary",
          disabled: !String(state[0].seriesName).trim(),
          onClick: function () {
            emit(p.owner, "design_save_version", state[0]);
            p.onClose();
          }
        }, "Save version"))));
  }
  function DesignSwitchModal(p) {
    var target = p.target || {};
    function select(resolution) {
      emit(p.owner, "design_switch", {
        seriesId: target.series_id,
        versionId: target.version_id,
        resolution: resolution
      });
      p.onClose();
    }
    return e(Modal, {
      title: "Unsaved design changes",
      subtitle: "Choose what to do before loading " + val(target.label, "the selected version"),
      onClose: p.onClose
    }, e("div", { className: "ly-danger-callout" },
      e("strong", null, "The active design differs from its last saved version."),
      e("p", null, "Switching without saving will discard the current working changes, evaluations, optimisations, and simulations.")),
      e("div", { className: "ly-run-summary" },
        e("strong", null, val(target.series_name, "Saved design")),
        e("span", null, val(target.label, "") + (target.created ? " · " + target.created : ""))),
      e("footer", { className: "ly-modal-actions" },
        e(Button, { onClick: p.onClose }, "Cancel"),
        e(Button, { className: "ly-danger-quiet", onClick: function () { select("discard"); } }, "Discard and switch"),
        e(Button, { className: "ly-primary", onClick: function () { select("save"); } }, "Save version and switch")));
  }
  function DesignHistory(p) {
    var history = p.owner.designHistory || {};
    var records = list(history.records), groups = [];
    records.forEach(function (record) {
      var group = groups.filter(function (item) {
        return item.id === record.series_id;
      })[0];
      if (!group) {
        group = { id: record.series_id, name: record.series_name, versions: [] };
        groups.push(group);
      }
      group.versions.push(record);
    });
    groups.forEach(function (group) {
      group.versions.sort(function (left, right) {
        return Number(right.version_number) - Number(left.version_number);
      });
    });
    return e("div", { className: "ly-design-history" },
      e("div", { className: "ly-side-heading" },
        e("label", null, "Designs"),
        e(Button, {
          className: "ly-history-save", title: "Save current design version",
          onClick: function () { p.open("save-version"); }
        }, "Save version")),
      history.dirty ? e("div", { className: "ly-dirty-state" },
        e("i", null), e("span", null, "Unsaved changes")) : null,
      groups.length ? e("div", { className: "ly-design-series-list" },
        groups.map(function (group) {
          var activeSeries = group.id === history.currentSeries;
          return e("details", {
            key: group.id, className: "ly-design-series",
            open: activeSeries || groups.length === 1
          }, e("summary", null, e("span", null, group.name),
            e("small", null, group.versions.length)),
          group.versions.map(function (version) {
            var active = version.version_id === history.currentVersion;
            return e("button", {
              type: "button", key: version.version_id,
              className: "ly-design-version " + (active ? "active" : ""),
              title: "Saved " + val(version.created, ""),
              onClick: function () {
                if (active && !history.dirty) return;
                p.onSelect(version);
              }
            }, e("span", null, version.label),
              active ? e(Badge, { tone: "accent" }, "Current") : null);
          }));
        })) :
        e("p", { className: "ly-history-empty" },
          "No saved designs yet. Save a version to begin the history."));
  }
  function App(props) {
    var stored = initialDarkTheme("LibeRality.theme");
    var dark = React.useState(stored), tab = React.useState("overview"), modal = React.useState(null);
    var selectedArm = React.useState(list(props.arms)[0] ? props.arms[0].id : null);
    var modelBrowser = React.useState(props.modelBrowser || { catalogue: { records: [], messages: {} }, preview: null, selectedKey: "", busy: false });
    var task = window.LibeRDesign.taskState.use(React, props.inputId, props.task);
    var previousEvaluation = React.useRef(props.evaluation && props.evaluation.id);
    var previousOptimisation = React.useRef(props.optimisation && props.optimisation.elapsed);
    var previousSimulation = React.useRef(props.simulation && props.simulation.elapsed);
    var evaluationMounted = React.useRef(false), optimisationMounted = React.useRef(false), simulationMounted = React.useRef(false);
    props.status = Object.assign({}, props.status || {}, { task: task, inputId: props.inputId });
    function open(value) { modal[1](typeof value === "string" ? { type: value } : value); }
    function close() { modal[1](null); }
    function selectDesign(record) {
      var history = props.designHistory || {};
      if (history.dirty) {
        open({ type: "switch-design", item: record });
      } else {
        emit(props, "design_switch", {
          seriesId: record.series_id, versionId: record.version_id
        });
      }
    }
    React.useEffect(function () { storeTheme(dark[0], "LibeRality.theme"); }, [dark[0]]);
    React.useEffect(function () {
      var available = list(props.arms);
      if (!available.some(function (x) { return x.id === selectedArm[0]; })) {
        selectedArm[1](available[0] ? available[0].id : null);
      }
    }, [list(props.arms).map(function (x) { return x.id; }).join("|")]);
    React.useEffect(function () {
      var id = props.evaluation && props.evaluation.id;
      if (evaluationMounted.current && id && id !== previousEvaluation.current) tab[1]("precision");
      evaluationMounted.current = true;
      previousEvaluation.current = id;
    }, [props.evaluation && props.evaluation.id]);
    React.useEffect(function () {
      var id = props.optimisation && props.optimisation.elapsed;
      if (optimisationMounted.current && id && id !== previousOptimisation.current) tab[1]("optimisation");
      optimisationMounted.current = true;
      previousOptimisation.current = id;
    }, [props.optimisation && props.optimisation.elapsed]);
    React.useEffect(function () {
      var id = props.simulation && props.simulation.elapsed;
      if (simulationMounted.current && id && id !== previousSimulation.current) tab[1]("simulation");
      simulationMounted.current = true;
      previousSimulation.current = id;
    }, [props.simulation && props.simulation.elapsed]);
    React.useEffect(function () {
      function update(event) {
        var detail = event.detail || {};
        modelBrowser[1](function (current) {
          return Object.assign({}, current, detail, { catalogue: detail.catalogue || current.catalogue });
        });
        if (detail.applied) close();
      }
      window.addEventListener("liberality:model-browser", update);
      return function () { window.removeEventListener("liberality:model-browser", update); };
    }, []);
    var design = props.design || {}, evaluation = props.evaluation || {}, info = evaluation.information || {};
    var optimisation = props.optimisation || {}, simulation = props.simulation;
    var arm = list(props.arms).filter(function (x) { return x.id === selectedArm[0]; })[0] || list(props.arms)[0];
    var workflow = props.workflow || {};
    var tabs = [
      ["overview", "Overview"],
      ["model", "Model", 1, workflow.modelReady],
      ["schedule", "Trial design", 2, workflow.designReady],
      ["objectives", "Objectives", 3, workflow.objectivesReady],
      ["precision", "Precision", 4, workflow.evaluated],
      ["robustness", "Robustness", 5, workflow.robustnessEvaluated],
      ["optimisation", "Optimisation", 6, workflow.optimised],
      ["simulation", "Simulation", 7, workflow.simulated]
    ];
    function evaluateButton() {
      var violated = Number((props.workflow || {}).violatedConstraints || 0);
      return e(Button, {
        className: "ly-primary", icon: "◎", disabled: task.running,
        title: violated ? violated + " declared constraint(s) are currently violated; evaluation will report them." : "Evaluate expected information and precision",
        onClick: function () { emit(props, "evaluate"); }
      }, violated ? "Evaluate with " + violated + " warning" : "Evaluate design");
    }
    function body() {
      if (tab[0] === "overview") return e("div", { className: "ly-stack" },
        e("div", { className: "ly-metric-grid" },
          e(Metric, { label: "Subjects", value: fmt(design.subjects, 0), detail: list(props.arms).length + " arms" }),
          e(Metric, { label: "Expected cost", value: fmt(design.cost, 0), detail: design.costUnit || "declared cost units" }),
          e(Metric, { label: "Criterion", value: val(props.criterion && props.criterion.guidance && props.criterion.guidance.label, props.criterion && props.criterion.type), detail: val(props.criterion && props.criterion.direction, "maximise") }),
          e(Metric, { label: "Information rank", value: info.rank === undefined ? "Not evaluated" : info.rank + "/" + info.dimension, detail: info.condition ? "condition " + fmt(info.condition, 2) : "" })),
        e(Panel, { title: "Clinical trial architecture", subtitle: design.description, actions: e(Button, { className: "ly-quiet", onClick: function () { open("identity"); } }, "Edit details") }, e(SchedulePlot, { arms: props.arms })),
        e(Panel, {
          title: "Declared constraints", subtitle: "Operational and statistical feasibility",
          actions: e(Button, { className: "ly-quiet", onClick: function () { tab[1]("objectives"); } }, "Manage")
        }, e(Table, { rows: props.constraints, columns: [
          { key: "name", label: "Constraint" }, { key: "value", label: "Value", format: fmt },
          { key: "limit", label: "Limit", format: fmt },
          { key: "feasible", label: "Status", format: function (x) { return x ? "Feasible" : "Violated"; } }
        ], onRowClick: function (row) { open({ type: "constraint-details", item: row }); } })),
        e("div", { className: "ly-page-actions" }, evaluateButton()));
      if (tab[0] === "model") return e("div", { className: "ly-stack" },
        e(Panel, { title: "Structural and statistical model", subtitle: "The model is copied into this design with immutable provenance" },
          e(ModelSummary, { model: props.model, owner: props, browser: modelBrowser[0], editable: true })),
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
          e(Table, { rows: props.model.parameters, columns: [
            { key: "type", label: "Type" }, { key: "name", label: "Parameter" },
            { key: "value", label: "Value", format: fmt },
            { key: "lower", label: "Lower", format: function (x, row) { return row.type !== "THETA" && Number(x) === 0 ? "Not set" : fmt(x); } },
            { key: "upper", label: "Upper", format: function (x, row) { return row.type !== "THETA" && Number(x) === 0 ? "Not set" : fmt(x); } },
            { key: "fixed", label: "Fixed", format: function (x) { return x ? "Yes" : "No"; } }
          ] })));
      if (tab[0] === "schedule") return e("div", { className: "ly-stack" },
        e(Panel, {
          title: "Dose and observation schedule", subtitle: "Dose markers are vertical; samples are circular",
          actions: e(Button, { className: "ly-primary ly-quiet", onClick: function () { open({ type: "arm", item: null }); } }, "+ Add arm")
        }, e(SchedulePlot, { arms: props.arms })),
        e("div", { className: "ly-card-grid" }, list(props.arms).map(function (a) {
          return e("article", { className: "ly-arm-card", key: a.id, onClick: function () { selectedArm[1](a.id); } },
            e("header", null, e("strong", null, a.name), e(Badge, { tone: a.id === selectedArm[0] ? "accent" : "neutral" }, a.size + " subjects")),
            e("p", null, a.samples + " samples per subject · " + a.population),
            e("small", null, list(a.samplingTimes).map(function (x) { return fmt(x, 2); }).join(", ") + " h"),
            e("div", { className: "ly-card-actions" },
              e(Button, { onClick: function (ev) { ev.stopPropagation(); selectedArm[1](a.id); open({ type: "arm", item: a }); } }, "Edit arm")));
        })));
      if (tab[0] === "objectives") return e("div", { className: "ly-stack" },
        e(Panel, {
          title: "Design objective", subtitle: val(props.criterion && props.criterion.guidance && props.criterion.guidance.summary, ""),
          actions: e(Button, { className: "ly-help-button", title: "Detailed criterion explanation", onClick: function () { open({ type: "criterion-help", item: props.criterion.guidance }); } }, "?")
        }, e(CriterionPicker, { owner: props, open: open })),
        e("div", { className: "ly-two" },
          e(Panel, { title: "Endpoints", subtitle: "Outcomes contributing information", actions: e(Button, { className: "ly-quiet", onClick: function () { open({ type: "endpoint", item: null }); } }, "+ Add") },
            e(DefinitionList, { rows: props.endpoints, onEdit: function (x) { open({ type: "endpoint", item: x }); }, detail: function (x) { return x.type + " · DVID " + x.dvid; } })),
          e(Panel, { title: "Scenarios", subtitle: "Parameter and operational uncertainty", actions: e(Button, { className: "ly-quiet", onClick: function () { open({ type: "scenario", item: null }); } }, "+ Add") },
            e(DefinitionList, { rows: props.scenarios, onEdit: function (x) { open({ type: "scenario", item: x }); }, detail: function (x) { return fmt(100 * x.probability, 1) + "% weight · " + fmt(100 * x.adherence, 0) + "% adherence"; } }))),
        e("div", { className: "ly-two" },
          e(Panel, { title: "Optimisable variables", subtitle: "Permitted design space", actions: e(Button, { className: "ly-quiet", onClick: function () { open({ type: "variable", item: null }); } }, "+ Add") },
            e(DefinitionList, { rows: props.variables, emptyTitle: "No optimisable variables", emptyDetail: "Add variables before running a finite-dimensional optimisation.", onEdit: function (x) { open({ type: "variable", item: x }); }, detail: function (x) { return x.target.replace(/_/g, " ") + " · " + x.arm + " · " + fmt(x.lower) + " to " + fmt(x.upper); } })),
          e(Panel, { title: "Constraints", subtitle: "Feasibility rules", actions: e(Button, { className: "ly-quiet", onClick: function () { open({ type: "constraint", item: null }); } }, "+ Add") },
            e(DefinitionList, { rows: props.constraintDefinitions, emptyTitle: "No constraints", emptyDetail: "Add operational, resource or statistical limits.", onEdit: function (x) { open({ type: "constraint", item: x }); }, detail: function (x) { return x.type.replace(/_/g, " ") + " · limit " + fmt(x.limit); } }))),
        e("div", { className: "ly-page-actions" }, evaluateButton()));
      if (tab[0] === "precision") return evaluation.id ? e("div", { className: "ly-stack" },
        e("div", { className: "ly-two" },
          e(Panel, { title: "Expected relative standard errors", subtitle: val(info.scenario, "Nominal scenario") }, e(BarChart, { rows: evaluation.precision, valueKey: "rse", suffix: "%" })),
          e(Panel, { title: "Criterion values", subtitle: "Direction is explicit for every objective" }, e(Table, { rows: evaluation.criteria, columns: [
            { key: "name", label: "Criterion" }, { key: "type", label: "Type" },
            { key: "value", label: "Value", format: function (x) { return fmt(x, 5); } }, { key: "direction", label: "Direction" }
          ] }))),
        e("div", { className: "ly-page-actions" }, e(Button, { onClick: function () { emit(props, "evaluate"); } }, "Re-evaluate design"), e(Button, { className: "ly-primary", onClick: function () { open("optimise"); } }, "Optimise this design"))) :
        e(Empty, { icon: "◎", title: "Design not evaluated", detail: "Complete the model, trial design and objective, then evaluate expected information and precision." });
      if (tab[0] === "robustness") return e("div", { className: "ly-two" },
        e(Panel, { title: "Design scenarios", subtitle: "Parameter and operational uncertainty" }, e(Table, { rows: props.scenarios, columns: [
          { key: "name", label: "Scenario" }, { key: "probability", label: "Weight", format: function (x) { return fmt(100 * x, 1) + "%"; } },
          { key: "adherence", label: "Adherence", format: function (x) { return fmt(100 * x, 0) + "%"; } },
          { key: "dropout", label: "Dropout", format: function (x) { return fmt(100 * x, 0) + "%"; } },
          { key: "missedSample", label: "Missed", format: function (x) { return fmt(100 * x, 0) + "%"; } }
        ] })),
        e(Panel, { title: "Information diagnostics", subtitle: "Numerical transparency across scenarios" }, info.rank === undefined ?
          e(Empty, { title: "Not evaluated", detail: "Run an evaluation to calculate scenario information." }) :
          e("div", { className: "ly-diagnostics" }, e(Metric, { label: "Log determinant", value: fmt(info.logDeterminant, 4) }), e(Metric, { label: "Condition number", value: fmt(info.condition, 3) }), e("p", null, val(info.diagnostics && info.diagnostics.method, "")), e("p", null, "Prediction derivatives: " + val(info.diagnostics && info.diagnostics.prediction_derivatives, "")), e(Table, { rows: evaluation.robustness, columns: [{ key: "scenario", label: "Scenario" }, { key: "rank", label: "Rank" }, { key: "condition", label: "Condition", format: fmt }, { key: "logDeterminant", label: "Log determinant", format: fmt }] }))));
      if (tab[0] === "optimisation") return e("div", { className: "ly-stack" },
        e(Panel, {
          title: "Optimisation convergence", subtitle: optimisation.method ? optimisation.method + " · " + optimisation.evaluations + " evaluations" : "No optimisation has run",
          actions: e(Button, { className: "ly-primary ly-quiet", disabled: !list(props.variables).length, onClick: function () { open("optimise"); } }, optimisation.method ? "Optimise again" : "Start optimisation")
        }, e(TracePlot, { rows: optimisation.trace })),
        e(Panel, { title: "Optimisable variables", subtitle: "Current values and permitted design space", actions: e(Button, { className: "ly-quiet", onClick: function () { open({ type: "variable", item: null }); } }, "+ Add variable") },
          e(Table, { rows: props.variables, columns: [
            { key: "name", label: "Variable" }, { key: "target", label: "Target" }, { key: "arm", label: "Arm" },
            { key: "current", label: "Current", format: fmt }, { key: "lower", label: "Lower", format: fmt },
            { key: "upper", label: "Upper", format: fmt }, { key: "type", label: "Type" }
          ] })));
      var endpointCurves = simulation ? list(simulation.endpointCurves) : [], nca = simulation && simulation.nca ? simulation.nca : {};
      var endpointNames = Array.from(new Set(endpointCurves.map(function (x) { return x.endpoint; })));
      return e("div", { className: "ly-stack" },
        e(Panel, {
          title: "Empirical trial simulation", subtitle: simulation ? simulation.n + " replicated trials in " + fmt(simulation.elapsed, 2) + " seconds" : "Not run",
          actions: e(Button, { className: "ly-primary ly-quiet", onClick: function () { open("simulate"); } }, simulation ? "Simulate again" : "Simulate trials")
        }, simulation ? e("div", null,
          e("div", { className: "ly-metric-grid" }, e(Metric, { label: "Trials", value: simulation.n }), e(Metric, { label: "Analysis", value: simulation.method }), e(Metric, { label: "Convergence", value: simulation.convergence === null || simulation.convergence === undefined ? "Not fitted" : fmt(100 * simulation.convergence, 1) + "%" })),
          e(Table, { rows: simulation.estimates, columns: [{ key: "parameter", label: "Parameter" }, { key: "mean", label: "Mean", format: fmt }, { key: "bias", label: "Bias", format: fmt }, { key: "rmse", label: "RMSE", format: fmt }] })) :
          e(Empty, { title: "No trial simulations", detail: "Simulate complete studies to verify theoretical information and operational robustness." })),
        simulation && endpointNames.length ? endpointNames.map(function (name) {
          var rows = endpointCurves.filter(function (x) { return x.endpoint === name; });
          return e(Panel, { key: name, title: name + " simulations", subtitle: "Median and 90% simulated interval across subjects and replicated trials" },
            e(EndpointSimulationPlot, { rows: rows }),
            e(Table, { rows: rows, columns: [{ key: "arm", label: "Arm" }, { key: "time", label: "Time", format: fmt }, { key: "n", label: "N" }, { key: "mean", label: "Mean", format: fmt }, { key: "median", label: "Median", format: fmt }, { key: "lower", label: "5th", format: fmt }, { key: "upper", label: "95th", format: fmt }] }));
        }) : null,
        simulation ? e(Panel, { title: "Noncompartmental exposure summaries", subtitle: val(nca.backend, "LibeRation native C++ NCA") },
          list(nca.summary).length ? e(Table, { rows: nca.summary, columns: [{ key: "endpoint", label: "Endpoint" }, { key: "arm", label: "Arm" }, { key: "metric", label: "NCA metric" }, { key: "n", label: "N" }, { key: "median", label: "Median", format: fmt }, { key: "lower", label: "5th", format: fmt }, { key: "upper", label: "95th", format: fmt }] }) : e(Table, { rows: nca.applicability, columns: [{ key: "endpoint", label: "Endpoint" }, { key: "arm", label: "Arm" }, { key: "applicable", label: "NCA", format: function (x) { return x ? "Available" : "Not applicable"; } }, { key: "reason", label: "Reason" }] })) : null);
    }
    var currentModal = modal[0] || {};
    return e("div", { className: "ly-app " + (dark[0] ? "ly-dark" : "ly-light") },
      e("header", { className: "ly-header" },
        e("div", { className: "ly-brand" }, props.icon ? e("img", { src: props.icon, alt: "" }) : e(Logo), e("div", null, e("strong", null, "LibeRality"), e("span", null, "Model-informed optimal trial design"))),
        e("div", { className: "ly-header-meta" }, e(Badge, { tone: "warning" }, "Research & teaching"), e("span", null, "v" + val(props.packageVersion, "0.1.0")), e("label", { className: "ly-switch" }, e("span", null, dark[0] ? "Dark" : "Light"), e("input", { type: "checkbox", checked: dark[0], onChange: function (x) { dark[1](x.target.checked); } }), e("i", null)))),
      e(Status, { status: props.status }),
      e("div", { className: "ly-layout" },
        e("aside", { className: "ly-sidebar" },
          e("div", { className: "ly-project" }, e("small", null, "ACTIVE DESIGN"), e("strong", null, val(design.name, "Untitled design")), e("span", null, val(design.modelType, "ADVAN" + val(design.advan, "-") + " / TRANS" + val(design.trans, "-"))),
            e("div", { className: "ly-project-actions" },
              e(Button, { className: "ly-quiet", onClick: function () { open("identity"); } }, "Edit details"),
              e(Button, { className: "ly-primary ly-quiet", onClick: function () { open("wizard"); } }, "Wizard"))),
          e(DesignHistory, { owner: props, open: open, onSelect: selectDesign }),
          e("nav", { className: "ly-actions" }, evaluateButton(),
            e(Button, { icon: "↗", disabled: !evaluation.id || !list(props.variables).length, onClick: function () { open("optimise"); } }, "Optimise design"),
            e(Button, { icon: "∿", onClick: function () { open("simulate"); } }, "Simulate trials"),
            props.queueAvailable ? e(Button, { icon: "⇧", onClick: function () { emit(props, "queue", { operation: "optimise", method: "auto" }); } }, "Submit to queue") : null),
          e("div", { className: "ly-side-section" }, e(CriterionPicker, { owner: props, open: open })),
          e("div", { className: "ly-side-section" },
            e("div", { className: "ly-side-heading" }, e("label", null, "Arms"), e(Button, { className: "ly-help-button", title: "Add design arm", onClick: function () { open({ type: "arm", item: null }); } }, "+")),
            list(props.arms).map(function (a) { return e("button", { className: a.id === selectedArm[0] ? "active" : "", key: a.id, onClick: function () { selectedArm[1](a.id); tab[1]("schedule"); } }, e("span", null, a.name), e("small", null, a.size)); }),
            arm ? e(Button, { className: "ly-quiet ly-wide", onClick: function () { open({ type: "arm", item: arm }); } }, "Edit selected arm") : null),
          e("div", { className: "ly-side-footer" },
            e(Button, { className: "ly-quiet", onClick: function () { open("save"); } }, "Export"),
            e(Button, { className: "ly-quiet", onClick: function () { open("load"); } }, "Import"),
            e(Button, { className: "ly-quiet", onClick: function () { open("report"); } }, "Report"),
            e(Button, { className: "ly-danger-quiet", onClick: function () { open("reset"); } }, "Reset"))),
        e("main", { className: "ly-main" },
          e("nav", { className: "ly-tabs", "aria-label": "Design workflow and results" },
            tabs.map(function (entry) {
              var active = tab[0] === entry[0], done = !!entry[3];
              return e("button", {
                key: entry[0],
                className: (active ? "active " : "") + (done ? "done" : ""),
                onClick: function () { tab[1](entry[0]); }
              }, entry[2] ? e("span", {
                className: "ly-tab-step", "aria-hidden": "true"
              }, done ? "\u2713" : String(entry[2])) : null,
              e("strong", null, entry[1]));
            })),
          e("div", { className: "ly-content" }, body())),
        e("aside", { className: "ly-inspector" },
          e("header", null, e("small", null, "SELECTED ARM"), e("strong", null, arm ? arm.name : "Study")),
          arm ? e("div", { className: "ly-inspect-list" },
            e("div", null, e("span", null, "Subjects"), e("strong", null, arm.size)),
            e("div", null, e("span", null, "Samples"), e("strong", null, arm.samples)),
            e("div", null, e("span", null, "Population"), e("strong", null, arm.population)),
            e("div", null, e("span", null, "Sample volume"), e("strong", null, fmt(arm.sampleVolume, 1)))) : null,
          e("h4", null, "Current objective"),
          e("div", { className: "ly-endpoint" }, e("strong", null, val(props.criterion && props.criterion.guidance && props.criterion.guidance.label, props.criterion && props.criterion.type)), e("span", null, val(props.criterion && props.criterion.direction, ""))),
          e("h4", null, "Feasibility"),
          e("button", { type: "button", className: "ly-feasibility-link " + (props.workflow && props.workflow.violatedConstraints ? "ly-warning-text" : "ly-success-text"), onClick: function () { open({ type: "constraint-details", item: null }); } }, props.workflow && props.workflow.violatedConstraints ? props.workflow.violatedConstraints + " constraint(s) currently violated — view details" : "All evaluated structural constraints are feasible — view details"),
          e("h4", null, "Endpoints"),
          list(props.endpoints).map(function (x) { return e("div", { className: "ly-endpoint", key: x.id }, e("strong", null, x.name), e("span", null, x.type + " · DVID " + x.dvid)); }),
          e("h4", null, "Reproducibility"),
          e("p", { className: "ly-muted" }, "Every result retains model, design, scenario, criterion, seed, version, and numerical diagnostics."))),
      currentModal.type === "identity" ? e(DesignIdentityModal, { owner: props, design: design, onClose: close }) : null,
      currentModal.type === "wizard" ? e(DesignWizardModal, { owner: props, onClose: close }) : null,
      currentModal.type === "save-version" ? e(SaveDesignVersionModal, { owner: props, onClose: close }) : null,
      currentModal.type === "switch-design" ? e(DesignSwitchModal, { owner: props, target: currentModal.item, onClose: close }) : null,
      currentModal.type === "arm" ? e(ArmModal, { owner: props, arm: currentModal.item, onClose: close }) : null,
      currentModal.type === "endpoint" ? e(EndpointModal, { owner: props, item: currentModal.item, onClose: close }) : null,
      currentModal.type === "scenario" ? e(ScenarioModal, { owner: props, item: currentModal.item, onClose: close }) : null,
      currentModal.type === "variable" ? e(VariableModal, { owner: props, item: currentModal.item, onClose: close }) : null,
      currentModal.type === "constraint" ? e(ConstraintModal, { owner: props, item: currentModal.item, onClose: close }) : null,
      currentModal.type === "constraint-details" ? e(ConstraintDetailsModal, { rows: props.constraints, selected: currentModal.item, onClose: close }) : null,
      currentModal.type === "criterion-help" ? e(CriterionHelpModal, { item: currentModal.item, onClose: close }) : null,
      currentModal.type === "optimise" ? e(OptimiseModal, { owner: props, onClose: close }) : null,
      currentModal.type === "simulate" ? e(SimulateModal, { owner: props, onClose: close }) : null,
      currentModal.type === "save" ? e(FileModal, { owner: props, action: "save", title: "Export design", subtitle: "Write a portable LibeRality RDS design object", button: "Export", defaultPath: "LibeRality-design.rds", onClose: close }) : null,
      currentModal.type === "load" ? e(FileModal, { owner: props, action: "load", title: "Import design", subtitle: "Open a trusted portable LibeRality RDS design", button: "Import", defaultPath: "LibeRality-design.rds", onClose: close }) : null,
      currentModal.type === "report" ? e(FileModal, { owner: props, action: "report", title: "Generate report", subtitle: "Write a self-contained HTML design report", button: "Generate", defaultPath: "LibeRality-report.html", onClose: close }) : null,
      currentModal.type === "reset" ? e(ConfirmModal, {
        title: "Reset design?", subtitle: "Restore the teaching example",
        warning: "The active in-memory design and unsaved results will be replaced.",
        button: "Reset design", onClose: close,
        onConfirm: function (confirmation) { emit(props, "reset", { confirmation: confirmation }); close(); }
      }) : null);
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
