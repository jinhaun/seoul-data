(() => {
  'use strict';
  const byId = id => document.getElementById(id);
  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const number = value => Math.round(value).toLocaleString('ko-KR');
  const compact = value => value >= 10000 ? (value / 10000).toFixed(1).replace(/\.0$/, '') + '만' : number(value);
  const state = {data:null, place:null, weekday:5, hour:14, months:1, view:'average', manifest:null, date:null, day:null};
  const periodCache = new Map(), dayCache = new Map();
  let periodRequest=0, dayRequest=0, sliderFrame=0;
  const dotDate = value => value ? value.replaceAll('-','.') : '자료 없음';
  const validDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value||'') && !Number.isNaN(Date.parse(value+'T00:00:00Z')) && new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;
  const periodName = () => state.months===12 ? '최근 1년' : `최근 ${state.months}개월`;
  const error = message => {byId('visitError').hidden=!message;byId('visitError').textContent=message||'';};
  async function getJson(path) {
    const r=await fetch(path,{cache:'no-store'});
    if(!r.ok)throw new Error('자료 응답 실패');
    return r.json();
  }
  const colors = ['#e6f3ed','#b9ddcd','#86c0b5','#4c9b95','#17545c'];
  const expected = weekday => state.data.period.expected_dates[weekday];
  const cell = (place, w=state.weekday, h=state.hour) => place.grid[w][h];
  function updateUrl() {
    const url = new URL(location.href);
    url.searchParams.set('place', state.place.name);
    url.searchParams.set('weekday', state.weekday);
    url.searchParams.set('hour', state.hour);
    url.searchParams.set('months',state.months);
    url.searchParams.set('view',state.view);
    if(state.date)url.searchParams.set('date',state.date);
    history.replaceState(null, '', url);
  }
  function renderGrid() {
    const mode = byId('visitHours').value;
    const hours = Array.from({length:24}, (_, i) => i).filter(h => mode === 'all' || (mode === 'night' ? h < 9 : h >= 9));
    const values = state.place.grid.flat().map(c => c[0]).filter(v => v !== null);
    const low = Math.min(...values), high = Math.max(...values);
    byId('visitScaleRange').textContent = values.length ? `${number(low)}~${number(high)}명` : '자료 없음';
    let table = '<table class="visit-heat"><caption>인구는 범위 중앙값의 평균입니다. 각 칸의 날짜 수를 함께 비교하세요.</caption><thead><tr><th scope="col">시간</th>';
    table += state.data.weekdays.map((d,w) => `<th scope="col">${d}<br><span>${expected(w)}일 중</span></th>`).join('') + '</tr></thead><tbody>';
    for (const h of hours) {
      table += `<tr><th scope="row">${String(h).padStart(2,'0')}시</th>`;
      state.data.weekdays.forEach((d,w) => {
        const c = cell(state.place,w,h), missing = c[0] === null;
        const level = missing ? 0 : Math.min(4,Math.floor((c[0]-low) / (high-low || 1) * 5));
        const selected = w === state.weekday && h === state.hour;
        const label = `${d}요일 ${h}시, ${missing ? '자료 없음' : `평균 ${number(c[0])}명`}, ${expected(w)}일 중 ${c[1]}일 관측`;
        table += `<td><button class="visit-cell" type="button" data-weekday="${w}" data-hour="${h}" data-missing="${missing}" aria-label="${escape(label)}" aria-pressed="${selected}" ${missing ? '' : `style="background:${colors[level]};color:${level===4?'#ffffff':'#102a2d'}"`}><span>${missing?'—':compact(c[0])}</span><small>${c[1]}/${expected(w)}일</small></button></td>`;
      });
      table += '</tr>';
    }
    byId('visitGrid').innerHTML = table + '</tbody></table>';
  }
  function renderDetail() {
    const c = cell(state.place), weekday = state.data.weekdays[state.weekday];
    byId('visitDetailTitle').textContent = `${state.place.name} · ${weekday}요일 ${state.hour}시`;
    byId('visitValue').textContent = c[0] === null ? '자료 없음' : `약 ${number(c[0])}명`;
    const possible=state.data.period.possible_dates[state.weekday];
    byId('visitSample').textContent = `관측 ${c[1]}일 / 기간 내 해당 요일 ${expected(state.weekday)}일 · 수집 전 ${expected(state.weekday)-possible}일 · 수집 시작 후 누락 ${possible-c[1]}일`;
    byId('visitDates').textContent = c[4].length ? `관측 날짜: ${c[4].map(d=>d.slice(5).replace('-','/')).join(', ')}` : '이 시간에는 관측 자료가 없습니다. 0명으로 계산하지 않았습니다.';
    byId('visitBounds').textContent = c[0] === null ? '' : `인구 추정 범위 평균: ${number(c[2])}~${number(c[3])}명. 표시 인구는 범위 중앙값의 평균입니다.`;
    byId('visitWeekday').value = state.weekday;
    byId('visitHour').value = state.hour;
    const sat = cell(state.place,5,state.hour), sun = cell(state.place,6,state.hour);
    if (sat[0] !== null && sun[0] !== null) {
      const difference = sat[0]-sun[0];
      let comparison = difference === 0 ? '두 요일의 평균이 같습니다.' : `${difference>0?'일요일':'토요일'}이 ${number(Math.abs(difference))}명 적었습니다.`;
      if (difference && sat[0] > 0 && difference > 0) comparison = `일요일이 토요일보다 약 ${(difference/sat[0]*100).toFixed(1)}% 적었습니다.`;
      byId('visitHighlight').textContent = `${state.place.name} ${state.hour}시 · 토요일 ${number(sat[0])}명(${sat[1]}일), 일요일 ${number(sun[0])}명(${sun[1]}일). ${comparison}`;
    } else {
      byId('visitHighlight').textContent = `${state.place.name}은 선택한 ${state.data.period.days}일 중 ${state.place.observed_dates.length}일에 관측됐습니다. 칸마다 관측 횟수를 확인해 비교해 주세요.`;
    }
    byId('visitDaily').innerHTML = '<caption>24시간 자료가 모두 있는 날만 계산한 하루 평균 인구</caption><thead><tr><th scope="col">구분</th>'+state.data.weekdays.map(d=>`<th scope="col">${d}</th>`).join('')+'</tr></thead><tbody><tr><th scope="row">평균 인구</th>'+state.place.daily.map(d=>`<td>${d.mean===null?'자료 없음':compact(d.mean)+'명'}</td>`).join('')+'</tr><tr><th scope="row">완전 관측일</th>'+state.place.daily.map(d=>`<td>${d.n}일</td>`).join('')+'</tr></tbody>';
  }
  function renderRanking() {
    const desc = byId('visitOrder').value === 'desc';
    const ranked = state.data.places.filter(p=>cell(p)[0] !== null).sort((a,b)=>(cell(a)[0]-cell(b)[0])*(desc?-1:1)||a.name.localeCompare(b.name,'ko'));
    byId('visitRankNote').textContent = `${state.data.weekdays[state.weekday]}요일 ${state.hour}시 · ${desc?'인구 많은':'인구 적은'} 순 10곳 · ${periodName()}`;
    byId('visitRanking').innerHTML = ranked.slice(0,10).map((p,i)=>`<li><button class="visit-rank-item" type="button" data-place="${escape(p.name)}" aria-label="${escape(p.name)} 시간표 보기"><span>${i+1}</span><span>${escape(p.name)}<small>${cell(p)[1]}/${expected(state.weekday)}일 관측${cell(p)[1]<2?' · 자료 적음':''}</small></span><strong>${number(cell(p)[0])}명</strong></button></li>`).join('') || '<li>이 시간에 비교할 자료가 없습니다.</li>';
  }
  function render() { if(!state.data)return;renderGrid(); renderDetail(); renderRanking(); if(state.view==='history')renderHistory();updateDownload();updateUrl(); }
  function selectTime(w,h) {
    state.weekday=Number(w);state.hour=Number(h);
    const mode=byId('visitHours');
    if ((mode.value==='day' && state.hour<9)||(mode.value==='night'&&state.hour>=9)) mode.value='all';
    render();
  }
  function updateDownload() {
    const a=byId('visitDownload');
    a.hidden=state.view==='history'&&!state.manifest.dates.includes(state.date);
    a.href=state.view==='history'?`data/realtime/${(state.date||'').slice(0,7)}/${state.date}.csv`:state.manifest.presets.find(p=>p.months===state.months).download;
    a.textContent=state.view==='history'?'이 날짜 원본 내려받기':'평균표 내려받기';
  }
  async function loadPeriod(months) {
    const request=++periodRequest;
    byId('visitPeriod').textContent='선택한 기간의 평균을 불러오고 있습니다…';
    byId('visitGrid').setAttribute('aria-busy','true');
    error('');
    try {
      let data=periodCache.get(months);
      if(!data){data=await getJson(state.manifest.presets.find(p=>p.months===months).path);periodCache.set(months,data);}
      if(request!==periodRequest)return;
      if(!data.places?.length||data.period.months!==months)throw new Error('평균표 형식 오류');
      state.months=months;state.data=data;
      state.place=data.places.find(p=>p.name===state.place?.name)||data.places.find(p=>p.name==='성수카페거리')||data.places[0];
      byId('visitPlace').innerHTML=data.places.map(p=>`<option value="${escape(p.name)}">${escape(p.name)}</option>`).join('');
      byId('visitPlace').disabled=false;byId('visitPlace').value=state.place.name;
      document.querySelectorAll('[data-months]').forEach(b=>b.setAttribute('aria-pressed',Number(b.dataset.months)===months));
      const p=data.period;
      byId('visitPeriod').textContent=`${periodName()} · ${dotDate(p.start)} ~ ${dotDate(p.end)} · ${p.days}일 · 오늘 제외 · 한국 시간`;
      byId('visitCoverage').textContent=`누적 수집 시작 ${dotDate(p.collection_start)} · 이 기간의 실제 자료 ${p.available_days}일${p.available_start?` (${dotDate(p.available_start)} ~ ${dotDate(p.available_end)})`:''}. ${p.before_collection_days?`수집 시작 전 ${p.before_collection_days}일은 자료가 없습니다. `:''}없는 날짜는 평균에 넣지 않으며, 자료가 쌓이면 자동으로 포함됩니다.`;
      byId('visitQuality').textContent=`선택 기간 원본 ${number(data.quality.source_rows)}행 중 잘못되거나 빈 인구 ${number(data.quality.invalid_rows)}행을 제외했습니다. 같은 날짜·장소·시간 ${number(data.quality.date_place_hours)}개를 계산했습니다.`;
      selectTime(state.weekday,state.hour);
    } catch(e) {
      if(request===periodRequest){byId('visitPeriod').textContent=state.data?`지금 보이는 표: ${periodName()} · ${dotDate(state.data.period.start)} ~ ${dotDate(state.data.period.end)}`:'평균표를 불러오지 못했습니다.';error('선택한 기간의 자료를 불러오지 못했습니다. 다른 기간을 고르거나 새로고침해 주세요.');}
    } finally {if(request===periodRequest)byId('visitGrid').removeAttribute('aria-busy');}
  }
  function setView(view) {
    state.view=view;
    byId('visitIntroText').textContent=view==='history'?'날짜를 고르고 시간 막대를 움직여 보세요. 그날 그 시간의 인구와 관측된 혼잡도가 함께 바뀝니다.':'장소와 기간을 골라 요일·시간을 비교해 보세요. 한 칸은 그 시간에 머물렀던 평균 인구입니다.';
    byId('visitAverage').hidden=view!=='average';byId('visitHistory').hidden=view!=='history';byId('visitHoursField').hidden=view==='history';
    document.querySelectorAll('[data-view]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.view===view));
    if(view==='history')loadDay(state.date);else selectTime(state.weekday,state.hour);
    updateDownload();updateUrl();
  }
  function historyCell(place) {return place?.hours[state.hour]||null;}
  function renderHistory() {
    const place=state.day?.places.find(p=>p.name===state.place.name), c=historyCell(place);
    byId('historyDetailTitle').textContent=`${state.place.name} · ${dotDate(state.date)} ${state.hour}시`;
    byId('historyValue').textContent=c?`약 ${number(c[0])}명`:'자료 없음';
    byId('historySample').textContent=c?`이 날짜 ${state.hour}시대 관측 ${c[3].length}회 · 한 시간 평균 인구`:'선택한 날짜·시간의 인구 관측이 없습니다. 0명이나 예측값으로 채우지 않았습니다.';
    byId('historyBounds').textContent=c?`인구 추정 범위 평균 ${number(c[1])}~${number(c[2])}명`:'';
    byId('historyQuickSummary').textContent=c?`평균 약 ${number(c[0])}명 · 관측 혼잡도 ${[...new Set(c[3].map(o=>o[3]||'자료 없음'))].join(' · ')} · ${c[3].length}회 관측`:'이 시간에는 자료가 없습니다. 다른 시간으로 움직여 보세요.';
    byId('historyObservations').innerHTML=c?c[3].map(o=>`<div class="history-observation"><span>${escape(o[0])}<br>${number(o[1])}~${number(o[2])}명</span><strong>${escape(o[3]||'혼잡도 없음')}</strong></div>`).join(''):'<p class="visit-help">혼잡도 관측 자료가 없습니다.</p>';
    byId('historySlider').value=state.hour;
    byId('historySlider').setAttribute('aria-valuetext',`${state.hour}시, ${c?'평균 '+number(c[0])+'명':'자료 없음'}`);
    byId('historyHourLabel').textContent=`${String(state.hour).padStart(2,'0')}:00~${String(state.hour).padStart(2,'0')}:59`;
    byId('historyPrevHour').disabled=state.hour===0;byId('historyNextHour').disabled=state.hour===23;
    const hours=place?.hours||Array(24).fill(null);
    byId('historyHours').innerHTML=hours.map((v,h)=>`<button type="button" data-history-hour="${h}" data-missing="${!v}" aria-pressed="${h===state.hour}" aria-label="${h}시 ${v?'평균 '+number(v[0])+'명':'자료 없음'}">${String(h).padStart(2,'0')}시<small>${v?compact(v[0]):'—'}</small></button>`).join('');
    const max=Math.max(1,...hours.filter(Boolean).map(v=>v[0]));
    const x=h=>54+h/23*646, y=v=>180-v/max*148;
    const segments=[];let segment=[];
    hours.forEach((v,h)=>{if(v)segment.push(`${x(h)},${y(v[0])}`);else if(segment.length){segments.push(segment);segment=[];}});
    if(segment.length)segments.push(segment);
    byId('historyChartTitle').textContent=`${state.place.name} · ${dotDate(state.date)} 인구 흐름`;
    byId('historyChart').innerHTML=`<svg viewBox="0 0 730 218" role="img" aria-label="${escape(state.place.name)} 선택 날짜의 시간별 평균 인구. 아래 시간 칸에서 정확한 값을 확인할 수 있습니다."><line x1="54" y1="180" x2="700" y2="180" stroke="#c6d8d4"/><line x1="54" y1="32" x2="700" y2="32" stroke="#e3ece8"/><text x="2" y="36" class="history-chart-label">${compact(max)}</text><text x="26" y="185" class="history-chart-label">0</text>${[0,6,12,18,23].map(h=>`<text x="${x(h)}" y="207" text-anchor="middle" class="history-chart-label">${h}시</text>`).join('')}${segments.map(s=>`<polyline points="${s.join(' ')}" fill="none" stroke="#167478" stroke-width="3"/>`).join('')}${hours.map((v,h)=>v?`<circle cx="${x(h)}" cy="${y(v[0])}" r="3" fill="#167478"/>`:'').join('')}<line x1="${x(state.hour)}" y1="20" x2="${x(state.hour)}" y2="180" stroke="#a56a20" stroke-width="2" stroke-dasharray="5 4"/>${c?`<circle cx="${x(state.hour)}" cy="${y(c[0])}" r="6" fill="#a56a20" stroke="white" stroke-width="2"/>`:''}</svg>`;
    const desc=byId('historyOrder').value==='desc';
    const ranked=(state.day?.places||[]).filter(p=>historyCell(p)).sort((a,b)=>(historyCell(a)[0]-historyCell(b)[0])*(desc?-1:1)||a.name.localeCompare(b.name,'ko'));
    byId('historyRankNote').textContent=`${dotDate(state.date)} ${state.hour}시 · ${desc?'인구 많은':'인구 적은'} 순 10곳`;
    byId('historyRanking').innerHTML=ranked.slice(0,10).map((p,i)=>`<li><button type="button" class="visit-rank-item" data-place="${escape(p.name)}"><span>${i+1}</span><span>${escape(p.name)}<small>이 시간 관측 ${historyCell(p)[3].length}회</small></span><strong>${number(historyCell(p)[0])}명</strong></button></li>`).join('')||'<li>이 날짜·시간에 비교할 자료가 없습니다.</li>';
  }
  async function loadDay(day) {
    const request=++dayRequest;
    state.date=day;state.day=null;
    byId('historyDate').value=day||'';
    byId('historyPrevDate').disabled=!day||day<=state.manifest.first_date;
    byId('historyNextDate').disabled=!day||day>=state.manifest.as_of;
    renderHistory();updateDownload();updateUrl();
    if(!validDate(day)||day<state.manifest.first_date||day>state.manifest.as_of){byId('historyNotice').textContent=`${dotDate(state.manifest.first_date)}부터 ${dotDate(state.manifest.as_of)} 사이 날짜를 선택해 주세요.`;return;}
    if(!state.manifest.dates.includes(day)){byId('historyNotice').textContent='이 날짜에는 저장된 관측 자료가 없습니다. 다른 날짜를 골라 주세요.';return;}
    byId('historyNotice').textContent='선택한 날짜의 기록을 불러오고 있습니다…';
    try {
      let data=dayCache.get(day);
      if(!data){data=await getJson(`site/history/${day.slice(0,7)}/${day}.json`);dayCache.set(day,data);}
      if(request!==dayRequest)return;
      if(data.date!==day)throw new Error('날짜 불일치');
      state.day=data;renderHistory();
      byId('historyNotice').textContent=`${dotDate(day)} · 한국 시간 · ${day===state.manifest.as_of?'오늘 자료는 수집 중이며 아직 오지 않은 시간은 비어 있습니다.':'그날 관측한 자료입니다.'} 날짜별 기록은 기간 평균과 별도로 조회합니다.`;
    } catch(e) {if(request===dayRequest){state.day=null;renderHistory();byId('historyNotice').textContent='이 날짜의 기록을 불러오지 못했습니다. 다른 날짜를 고르거나 다시 시도해 주세요.';}}
  }
  function moveDay(delta) {const d=new Date(state.date+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+delta);loadDay(d.toISOString().slice(0,10));}
  function historyTime(hour) {cancelAnimationFrame(sliderFrame);sliderFrame=0;state.hour=Math.max(0,Math.min(23,Number(hour)));renderHistory();updateUrl();}
  document.querySelectorAll('[data-months]').forEach(b=>b.addEventListener('click',()=>{if(state.manifest)loadPeriod(Number(b.dataset.months));}));
  document.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>{if(state.data)setView(b.dataset.view);}));
  byId('historyDate').addEventListener('change',()=>loadDay(byId('historyDate').value));
  byId('historyPrevDate').addEventListener('click',()=>moveDay(-1));byId('historyNextDate').addEventListener('click',()=>moveDay(1));
  byId('historyPrevHour').addEventListener('click',()=>historyTime(state.hour-1));byId('historyNextHour').addEventListener('click',()=>historyTime(state.hour+1));
  byId('historySlider').addEventListener('input',()=>{cancelAnimationFrame(sliderFrame);const h=byId('historySlider').value;sliderFrame=requestAnimationFrame(()=>historyTime(h));});
  byId('historyHours').addEventListener('click',e=>{const b=e.target.closest('[data-history-hour]');if(b){const h=Number(b.dataset.historyHour);historyTime(h);byId('historyHours').querySelector(`[data-history-hour="${h}"]`).focus({preventScroll:true});}});
  byId('historyOrder').addEventListener('change',renderHistory);
  byId('historyRanking').addEventListener('click',e=>{const b=e.target.closest('[data-place]');if(b){state.place=state.data.places.find(p=>p.name===b.dataset.place);byId('visitPlace').value=state.place.name;render();byId('visitPlace').focus();}});
  byId('visitGrid').addEventListener('click', e=>{
    const b=e.target.closest('button[data-weekday]'); if(!b)return;
    const w=Number(b.dataset.weekday),h=Number(b.dataset.hour);
    selectTime(w,h);
    byId('visitGrid').querySelector(`[data-weekday="${w}"][data-hour="${h}"]`).focus({preventScroll:true});
  });
  byId('visitRanking').addEventListener('click', e=>{
    const b=e.target.closest('button[data-place]');if(!b)return;
    state.place=state.data.places.find(p=>p.name===b.dataset.place);byId('visitPlace').value=state.place.name;render();byId('visitPlace').focus();
  });
  byId('visitPlace').addEventListener('change',()=>{state.place=state.data.places.find(p=>p.name===byId('visitPlace').value);render();});
  byId('visitHours').addEventListener('change',renderGrid);
  byId('visitWeekday').addEventListener('change',()=>selectTime(byId('visitWeekday').value,state.hour));
  byId('visitHour').addEventListener('change',()=>selectTime(state.weekday,byId('visitHour').value));
  byId('visitOrder').addEventListener('change',renderRanking);
  getJson('site/visit-manifest.json').then(async manifest=>{
    state.manifest=manifest;const query=new URL(location.href).searchParams;
    state.place={name:query.get('place')||'성수카페거리'};
    if(query.has('weekday')&&/^[0-6]$/.test(query.get('weekday')))state.weekday=Number(query.get('weekday'));
    if(query.has('hour')&&/^(\d|1\d|2[0-3])$/.test(query.get('hour')))state.hour=Number(query.get('hour'));
    const requestedDate=query.get('date');
    state.date=validDate(requestedDate)&&requestedDate>=manifest.first_date&&requestedDate<=manifest.as_of?requestedDate:[...manifest.dates].reverse().find(d=>d<manifest.as_of)||manifest.last_date||'';
    byId('historyDate').min=manifest.first_date||'';byId('historyDate').max=manifest.as_of;
    byId('visitWeekday').innerHTML=['월','화','수','목','금','토','일'].map((d,i)=>`<option value="${i}">${d}요일</option>`).join('');
    byId('visitHour').innerHTML=Array.from({length:24},(_,h)=>`<option value="${h}">${h}시</option>`).join('');
    const months=[1,3,6,12].includes(Number(query.get('months')))?Number(query.get('months')):1;
    await loadPeriod(months);
    if(state.data)setView(query.get('view')==='history'?'history':'average');
  }).catch(()=>{
    error('조회 자료를 불러오지 못했습니다. 잠시 뒤 새로고침해 주세요.');
    byId('visitHighlight').textContent='기존 실시간 자료는 아래에서 확인할 수 있습니다.';
  });
})();
