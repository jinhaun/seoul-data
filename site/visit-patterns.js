(() => {
  'use strict';
  const byId = id => document.getElementById(id);
  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const number = value => Math.round(value).toLocaleString('ko-KR');
  const compact = value => value >= 10000 ? (value / 10000).toFixed(1).replace(/\.0$/, '') + '만' : number(value);
  const state = {data:null, place:null, weekday:5, hour:14};
  const colors = ['#e6f3ed','#b9ddcd','#86c0b5','#4c9b95','#17545c'];
  const expected = weekday => state.data.period.expected_dates[weekday];
  const cell = (place, w=state.weekday, h=state.hour) => place.grid[w][h];
  function updateUrl() {
    const url = new URL(location.href);
    url.searchParams.set('place', state.place.name);
    url.searchParams.set('weekday', state.weekday);
    url.searchParams.set('hour', state.hour);
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
    byId('visitSample').textContent = `관측 ${c[1]}일 / 대상 ${expected(state.weekday)}일 · 누락 ${expected(state.weekday)-c[1]}일`;
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
      byId('visitHighlight').textContent = `${state.place.name}은 최근 30일 중 ${state.place.observed_dates.length}일에 관측됐습니다. 칸마다 관측 횟수를 확인해 비교해 주세요.`;
    }
    byId('visitDaily').innerHTML = '<caption>24시간 자료가 모두 있는 날만 계산한 하루 평균 인구</caption><thead><tr><th scope="col">구분</th>'+state.data.weekdays.map(d=>`<th scope="col">${d}</th>`).join('')+'</tr></thead><tbody><tr><th scope="row">평균 인구</th>'+state.place.daily.map(d=>`<td>${d.mean===null?'자료 없음':compact(d.mean)+'명'}</td>`).join('')+'</tr><tr><th scope="row">완전 관측일</th>'+state.place.daily.map(d=>`<td>${d.n}일</td>`).join('')+'</tr></tbody>';
  }
  function renderRanking() {
    const desc = byId('visitOrder').value === 'desc';
    const ranked = state.data.places.filter(p=>cell(p)[0] !== null).sort((a,b)=>(cell(a)[0]-cell(b)[0])*(desc?-1:1)||a.name.localeCompare(b.name,'ko'));
    byId('visitRankNote').textContent = `${state.data.weekdays[state.weekday]}요일 ${state.hour}시 · ${desc?'인구 많은':'인구 적은'} 순 10곳 · 같은 30일 기간`;
    byId('visitRanking').innerHTML = ranked.slice(0,10).map((p,i)=>`<li><button class="visit-rank-item" type="button" data-place="${escape(p.name)}" aria-label="${escape(p.name)} 시간표 보기"><span>${i+1}</span><span>${escape(p.name)}<small>${cell(p)[1]}/${expected(state.weekday)}일 관측${cell(p)[1]<2?' · 자료 적음':''}</small></span><strong>${number(cell(p)[0])}명</strong></button></li>`).join('') || '<li>이 시간에 비교할 자료가 없습니다.</li>';
  }
  function render() { renderGrid(); renderDetail(); renderRanking(); updateUrl(); }
  function selectTime(w,h) {
    state.weekday=Number(w);state.hour=Number(h);
    const mode=byId('visitHours');
    if ((mode.value==='day' && state.hour<9)||(mode.value==='night'&&state.hour>=9)) mode.value='all';
    render();
  }
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
  fetch('site/visit-patterns.json',{cache:'no-store'}).then(r=>{if(!r.ok)throw new Error('평균표 응답 실패');return r.json();}).then(data=>{
    if(!data.places?.length)throw new Error('장소 자료 없음');
    state.data=data;const query=new URL(location.href).searchParams;
    state.place=data.places.find(p=>p.name===query.get('place'))||data.places.find(p=>p.name==='성수카페거리')||data.places[0];
    if(query.has('weekday')&&/^[0-6]$/.test(query.get('weekday')))state.weekday=Number(query.get('weekday'));
    if(query.has('hour')&&/^(\d|1\d|2[0-3])$/.test(query.get('hour')))state.hour=Number(query.get('hour'));
    byId('visitPlace').innerHTML=data.places.map(p=>`<option value="${escape(p.name)}">${escape(p.name)}</option>`).join('');
    byId('visitPlace').disabled=false;byId('visitPlace').value=state.place.name;
    byId('visitWeekday').innerHTML=data.weekdays.map((d,i)=>`<option value="${i}">${d}요일</option>`).join('');
    byId('visitHour').innerHTML=Array.from({length:24},(_,h)=>`<option value="${h}">${h}시</option>`).join('');
    byId('visitPeriod').textContent=`${data.period.start.replaceAll('-','.')} ~ ${data.period.end.replaceAll('-','.')} · 오늘 제외 최근 ${data.period.days}일 · 한국 시간 · 새 자료 반영 후 자동 계산`;
    byId('visitQuality').textContent=`집계에 사용한 원본 ${number(data.quality.source_rows)}행 중 잘못되거나 빈 인구 ${number(data.quality.invalid_rows)}행을 제외했습니다. 같은 날짜·장소·시간 ${number(data.quality.date_place_hours)}개를 계산했습니다.${data.quality.conflicting_duplicates?' 같은 시각의 값이 서로 다른 경우 먼저 수집된 유효값을 사용했습니다.':''}`;
    selectTime(state.weekday,state.hour);
  }).catch(()=>{
    byId('visitPeriod').textContent='평균표를 불러오지 못했습니다. 잠시 뒤 새로고침하거나 평균표 내려받기를 이용해 주세요.';
    byId('visitPeriod').setAttribute('role','alert');
    byId('visitHighlight').textContent='기존 실시간 자료는 아래에서 확인할 수 있습니다.';
  });
})();
