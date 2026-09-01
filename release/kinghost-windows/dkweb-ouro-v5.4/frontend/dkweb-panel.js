(function () {
  "use strict";

  function element(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function money(value) {
    var number = Number(value || 0);
    return number.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  }

  function date(value) {
    if (!value) return "—";
    var parts = String(value).slice(0, 10).split("-");
    return parts.length === 3 ? parts[2] + "/" + parts[1] + "/" + parts[0] : String(value);
  }

  function section(title) {
    var block = element("section", "dk-section");
    block.appendChild(element("h2", "dk-section__title", title));
    return block;
  }

  function empty(text) {
    return element("p", "dk-empty", text);
  }

  function render(target, data) {
    target.textContent = "";
    var header = element("div", "dk-hero");
    header.appendChild(element("span", "dk-kicker", "HISTÓRICO LIVE CONNECT"));
    header.appendChild(element("h1", "dk-title", "Olá, " + (data.student.nome || "aluno") + "."));
    header.appendChild(element("p", "dk-subtitle", "Matrícula " + (data.student.matricula || "—") + " • Dados recuperados do DKWeb"));
    target.appendChild(header);

    var courses = section("Cursos e módulos");
    if (!data.courses || !data.courses.length) {
      courses.appendChild(empty("Nenhum curso histórico localizado."));
    } else {
      var grid = element("div", "dk-grid");
      data.courses.forEach(function (course) {
        var card = element("article", "dk-card");
        card.appendChild(element("h3", "dk-card__title", course.curso));
        card.appendChild(element("p", "dk-card__meta", "Situação: " + (course.situacao || "—")));
        card.appendChild(element("p", "dk-card__meta", "Matrícula: " + date(course.data_matricula)));
        var related = (data.modules || []).filter(function (module) {
          return String(module.id_aluno_curso) === String(course.id_aluno_curso);
        });
        if (related.length) {
          var list = element("ul", "dk-list");
          related.forEach(function (module) {
            var item = element("li", "dk-list__item");
            item.appendChild(element("span", "", module.modulo));
            item.appendChild(element("small", "", module.situacao || "—"));
            list.appendChild(item);
          });
          card.appendChild(list);
        }
        grid.appendChild(card);
      });
      courses.appendChild(grid);
    }
    target.appendChild(courses);

    var grades = section("Notas");
    if (!data.grades || !data.grades.length) {
      grades.appendChild(empty("Nenhuma avaliação registrada."));
    } else {
      var table = element("div", "dk-table");
      data.grades.forEach(function (grade) {
        var row = element("div", "dk-table__row");
        var description = element("div", "");
        description.appendChild(element("strong", "", grade.avaliacao));
        description.appendChild(element("small", "", grade.modulo + " • " + date(grade.data)));
        row.appendChild(description);
        row.appendChild(element("strong", "dk-grade", grade.nota));
        table.appendChild(row);
      });
      grades.appendChild(table);
    }
    target.appendChild(grades);

    var attendance = section("Frequência");
    if (!data.attendance || !data.attendance.length) {
      attendance.appendChild(empty("Nenhuma frequência registrada."));
    } else {
      var attendanceGrid = element("div", "dk-stats");
      data.attendance.forEach(function (item) {
        var total = Number(item.aulas_registradas || 0);
        var present = Number(item.presencas || 0);
        var percent = total ? Math.round((present / total) * 100) : 0;
        var stat = element("article", "dk-stat");
        stat.appendChild(element("strong", "dk-stat__value", percent + "%"));
        stat.appendChild(element("span", "", present + " presenças em " + total + " aulas"));
        stat.appendChild(element("small", "", "Última aula: " + date(item.ultima_aula)));
        attendanceGrid.appendChild(stat);
      });
      attendance.appendChild(attendanceGrid);
    }
    target.appendChild(attendance);

    var finance = section("Financeiro");
    if (!data.finance || !data.finance.length) {
      finance.appendChild(empty("Nenhum lançamento financeiro localizado."));
    } else {
      var financeTable = element("div", "dk-table");
      data.finance.forEach(function (entry) {
        var paid = entry.quitado === "S";
        var row = element("div", "dk-table__row");
        var description = element("div", "");
        description.appendChild(element("strong", "", entry.historico || "Parcela"));
        description.appendChild(element("small", "", "Vencimento: " + date(entry.vencimento)));
        var value = element("div", "dk-finance");
        value.appendChild(element("strong", "", money(paid ? entry.valor_pago : entry.valor)));
        value.appendChild(element("span", paid ? "dk-badge dk-badge--paid" : "dk-badge", paid ? "Pago" : "Em aberto"));
        row.appendChild(description);
        row.appendChild(value);
        financeTable.appendChild(row);
      });
      finance.appendChild(financeTable);
    }
    target.appendChild(finance);
  }

  async function mount(options) {
    var target = typeof options.target === "string" ? document.querySelector(options.target) : options.target;
    if (!target) throw new Error("dkweb_target_not_found");
    target.textContent = "";
    target.appendChild(element("p", "dk-loading", "Carregando histórico acadêmico…"));
    var headers = { "Content-Type": "application/json", Authorization: "Bearer " + options.token };
    if (options.apiKey) headers.apikey = options.apiKey;
    try {
      var result = await fetch(options.gatewayUrl + "?service=dkweb", {
        method: "POST",
        headers: headers,
        body: JSON.stringify({ action: "summary" }),
      });
      var data = await result.json();
      if (!result.ok || !data.ok) throw new Error(data.error || "dkweb_request_failed");
      render(target, data);
    } catch (error) {
      target.textContent = "";
      var identityErrors = ["identity_not_linked", "dkweb_student_not_found", "ambiguous_identity", "ouro_identity_incomplete"];
      var message = error && identityErrors.indexOf(error.message) !== -1
        ? "Seu acesso à Ouro está funcionando, mas ainda não encontramos a correspondência no histórico DKWeb. Fale com a Secretaria."
        : "Não foi possível carregar o histórico DKWeb agora. Tente novamente em alguns minutos.";
      target.appendChild(empty(message));
    }
  }

  window.LiveConnectDKWeb = { mount: mount };
})();
