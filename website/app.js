(() => {
  'use strict';
  const translatable = [...document.querySelectorAll('[data-en]')];
  const chinese = new Map(translatable.map(element => [element, element.innerHTML]));
  const accessible = [...document.querySelectorAll('[data-en-aria], [data-en-alt]')];
  const originalAttributes = new Map(accessible.map(element => [element, {
    label: element.getAttribute('aria-label'), alt: element.getAttribute('alt'),
  }]));
  const language = document.getElementById('language');
  let english = false;
  language.addEventListener('click', () => {
    english = !english;
    document.documentElement.lang = english ? 'en' : 'zh-CN';
    document.title = english ? 'waytty — Your machines. Your workspace.' : 'waytty — 连接你的机器，专注眼前的事';
    for (const element of translatable) {
      if (english) element.textContent = element.dataset.en;
      else element.innerHTML = chinese.get(element); // Only static, locally authored markup.
    }
    for (const element of accessible) {
      const original = originalAttributes.get(element);
      if (element.dataset.enAria) element.setAttribute('aria-label', english ? element.dataset.enAria : original.label);
      if (element.dataset.enAlt) element.setAttribute('alt', english ? element.dataset.enAlt : original.alt);
    }
    language.textContent = english ? '中文' : 'EN';
    language.setAttribute('aria-label', english ? '切换到中文' : 'Switch to English');
    const image = document.getElementById('connections-image');
    image.src = `./assets/connections-${english ? 'en' : 'zh'}.png`;
    image.closest('a').href = image.src;
  });

  const tabs = [...document.querySelectorAll('[role="tab"]')];
  function selectTab(selected, focus = false) {
    for (const tab of tabs) {
      const active = tab === selected;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
      document.getElementById(tab.getAttribute('aria-controls')).hidden = !active;
    }
    if (focus) selected.focus();
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectTab(tab));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next !== undefined) { event.preventDefault(); selectTab(tabs[next], true); }
    });
  });
})();
