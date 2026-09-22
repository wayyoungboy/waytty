(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const languageKey = "waytty.site.language";
  const languageButton = document.getElementById("language");
  const translatable = [...document.querySelectorAll("[data-en]")];
  const chinese = new Map(
    translatable.map((element) => [element, element.innerHTML]),
  );
  const accessible = [
    ...document.querySelectorAll("[data-en-aria], [data-en-alt]"),
  ];
  const originals = new Map(
    accessible.map((element) => [
      element,
      {
        label: element.getAttribute("aria-label"),
        alt: element.getAttribute("alt"),
      },
    ]),
  );
  let english = false;

  function setLanguage(value, persist = false) {
    english = value === "en";
    const lang = english ? "en" : "zh-CN";
    document.documentElement.lang = lang;
    document.title = english
      ? "waytty — Connect to your world. Stay in your flow."
      : "waytty — 连接远端，工作就在眼前。";
    for (const element of translatable) {
      if (english) element.textContent = element.dataset.en;
      else element.innerHTML = chinese.get(element); // Static, locally authored content only.
    }
    for (const element of accessible) {
      const original = originals.get(element);
      if (element.dataset.enAria)
        element.setAttribute(
          "aria-label",
          english ? element.dataset.enAria : original.label,
        );
      if (element.dataset.enAlt)
        element.setAttribute(
          "alt",
          english ? element.dataset.enAlt : original.alt,
        );
    }
    for (const image of document.querySelectorAll("[data-image-en]")) {
      image.src = english ? image.dataset.imageEn : image.dataset.imageZh;
      image.closest("a").href = image.src;
    }
    for (const link of document.querySelectorAll("[data-doc-link]")) {
      link.href = `https://github.com/wayyoungboy/waytty/blob/main/${english ? "README_EN.md" : "README.md"}`;
    }
    document.querySelector('meta[name="description"]').content = english
      ? "An open-source terminal workspace for developers and operations. SSH, SFTP, Linux monitoring and serial debugging. Local use without an account. Download the macOS release."
      : "waytty 是面向开发者与运维的开源终端工作区。SSH、SFTP、Linux 主机监控与串口调试，免登录本地使用。下载 macOS 版本。";
    document.querySelector('meta[property="og:title"]').content =
      document.title;
    document.querySelector('meta[property="og:locale"]').content = english
      ? "en_US"
      : "zh_CN";
    document.querySelector('meta[property="og:description"]').content = english
      ? "SSH, file transfers and host monitoring in one focused workspace. Local use without an account. Open source under MIT."
      : "SSH、文件传输与主机监控，收进一个顺手的工作区。本地免登录，MIT 开源。";
    languageButton.textContent = english ? "简体中文" : "English";
    languageButton.setAttribute(
      "aria-label",
      english ? "切换到简体中文" : "Switch to English",
    );
    if (persist) {
      try {
        localStorage.setItem(languageKey, lang);
      } catch {
        /* Private browsing may deny storage. */
      }
      const url = new URL(location.href);
      if (english) url.searchParams.set("lang", "en");
      else url.searchParams.delete("lang");
      history.replaceState(null, "", url);
    }
  }
  let savedLanguage;
  try {
    savedLanguage = localStorage.getItem(languageKey);
  } catch {
    /* Use default Chinese. */
  }
  const requestedLanguage = new URLSearchParams(location.search).get("lang");
  setLanguage(requestedLanguage ?? savedLanguage ?? "zh-CN");
  languageButton.addEventListener("click", () =>
    setLanguage(english ? "zh-CN" : "en", true),
  );

  const menu = document.getElementById("menu-toggle");
  const navigation = document.getElementById("navigation");
  function closeMenu() {
    navigation.classList.remove("is-open");
    menu.setAttribute("aria-expanded", "false");
  }
  menu.addEventListener("click", () => {
    const open = menu.getAttribute("aria-expanded") !== "true";
    menu.setAttribute("aria-expanded", String(open));
    navigation.classList.toggle("is-open", open);
  });
  navigation.addEventListener("click", (event) => {
    if (event.target.closest("a")) closeMenu();
  });
  document.addEventListener("keydown", (event) => {
    if (
      event.key === "Escape" &&
      menu.getAttribute("aria-expanded") === "true"
    ) {
      closeMenu();
      menu.focus();
    }
  });

  // Each tablist has its own selection and keyboard focus. Demo tabs must
  // never hide the independent application-screenshot gallery below.
  document.querySelectorAll('[role="tablist"]').forEach((tablist) => {
    const tabs = [...tablist.querySelectorAll('[role="tab"]')];
    function selectTab(selected, focus = false) {
      for (const tab of tabs) {
        const active = tab === selected;
        tab.setAttribute("aria-selected", String(active));
        tab.tabIndex = active ? 0 : -1;
        document.getElementById(tab.getAttribute("aria-controls")).hidden =
          !active;
        const copy = document.getElementById(tab.id.replace("tab-", "copy-"));
        if (copy) copy.hidden = !active;
      }
      if (focus) selected.focus();
    }
    tabs.forEach((tab, index) => {
      tab.addEventListener("click", () => selectTab(tab));
      tab.addEventListener("keydown", (event) => {
        let next;
        if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
        if (event.key === "ArrowLeft")
          next = (index - 1 + tabs.length) % tabs.length;
        if (event.key === "Home") next = 0;
        if (event.key === "End") next = tabs.length - 1;
        if (next !== undefined) {
          event.preventDefault();
          selectTab(tabs[next], true);
        }
      });
    });
  });

  const preview = document.getElementById("image-preview");
  const previewImage = document.getElementById("preview-image");
  const previewCaption = document.getElementById("preview-caption");
  let previewTrigger;
  document.querySelectorAll(".preview-link").forEach((link) => {
    link.addEventListener("click", (event) => {
      if (
        event.ctrlKey ||
        event.metaKey ||
        event.shiftKey ||
        event.altKey ||
        event.button !== 0 ||
        !preview.showModal
      )
        return;
      event.preventDefault();
      const image = link.querySelector("img");
      previewImage.src = link.href;
      previewImage.alt = image.alt;
      previewCaption.textContent = image.alt;
      previewTrigger = link;
      preview.showModal();
    });
  });
  document
    .getElementById("preview-close")
    .addEventListener("click", () => preview.close());
  preview.addEventListener("click", (event) => {
    if (event.target === preview) {
      const box = preview.getBoundingClientRect();
      if (
        event.clientX < box.left ||
        event.clientX > box.right ||
        event.clientY < box.top ||
        event.clientY > box.bottom
      )
        preview.close();
    }
  });
  preview.addEventListener("close", () => {
    previewImage.removeAttribute("src");
    previewTrigger?.focus({ preventScroll: true });
  });
})();
