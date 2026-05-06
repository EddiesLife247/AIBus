document.addEventListener('DOMContentLoaded', function () {
    const timetableContainer = document.querySelector('.timetable-container');
    const routesContainer = document.getElementById('routes-container');
    const timeDisplay = document.getElementById('current-time');
    const closeButton = document.getElementById('close-button');
    const nextBusContainer = document.getElementById('next-bus-container');
const inBusContainer = document.getElementById('in-bus-container');
const stoppingSign = document.getElementById('stopping-sign');


    closeButton.addEventListener('click', function() {
        // MODIFIED: Ensure the resource name matches your folder name exactly.
        fetch(`https://AIBus/close`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({})
        }).catch(err => console.error(err));
    });

    // --- Basic UI and Time Functions ---
    function updateTime() {
        const now = new Date();
        const hours = now.getHours().toString().padStart(2, '0');
        const minutes = now.getMinutes().toString().padStart(2, '0');
        timeDisplay.textContent = `${hours}:${minutes}`;
    }
    setInterval(updateTime, 1000);
    updateTime();

    // --- NUI Message Listener ---
    window.addEventListener('message', function (event) {
        const data = event.data;
        switch (data.action) {
            case 'openTimetable':
                timetableContainer.style.display = 'block';
                updateTimetable(data.busData);
                break;
            case 'closeTimetable':
                timetableContainer.style.display = 'none';
                break;
            case 'updateTimetable':
                updateTimetable(data.busData);
                break;
            case 'showNextBus':
                updateNextBusDisplay(data.nextBus);
                nextBusContainer.style.display = 'flex';
                break;
            case 'hideNextBus':
                nextBusContainer.style.display = 'none';
                break;
            // NEW CASES for the in-bus display
            case 'showInBusUI':
                updateInBusDisplay(data.data);
                inBusContainer.style.display = 'flex';
                break;
            case 'hideInBusUI':
                inBusContainer.style.display = 'none';
                break;
        case 'showStoppingSign':
            stoppingSign.style.display = 'block';
            break;
        case 'hideStoppingSign':
            stoppingSign.style.display = 'none';
            break;
        }
    });

    function updateInBusDisplay(data) {
        let content = `<div class="route-name">${data.routeName}</div>`;
        if (data.status === 'stopped') {
            content += `
                <div class="stop-info">
                    <span class="label">This is:</span>
                    <span class="stop-name">${data.currentStopName}</span>
                </div>
                <div class="stop-info">
                    <span class="label">Next Stop:</span>
                    <span class="next-stop-name">${data.nextStopName}</span>
                </div>
            `;
        } else { // Driving
            content += `
                <div class="stop-info">
                    <span class="label">Next Stop:</span>
                    <span class="next-stop-name">${data.nextStopName}</span>
                </div>
            `;
        }
        inBusContainer.innerHTML = content;
    }
    
    // --- UI Update Functions ---
    function updateTimetable(busData) {
        routesContainer.innerHTML = '';
        for (const routeName in busData) {
            const route = busData[routeName];
            const routeElement = document.createElement('div');
            routeElement.className = 'route';
            routeElement.innerHTML = `<div class="route-header">${routeName}</div>`;

            if (route.buses.length > 0) {
                route.buses.forEach((bus, index) => {
                    const progress = (bus.currentStopIndex / bus.totalStops) * 100;
                    const etaText = bus.eta ? `${bus.eta} min` : 'N/A';
                    const busEntry = document.createElement('div');
                    busEntry.className = 'bus-entry';
                    busEntry.innerHTML = `
                        <div class="bus-info">
                            <img src="https://img.icons8.com/ios-filled/50/94a3b8/bus.png" alt="bus-icon" class="bus-icon">
                            <div class="location-details">
                                <div class="status">Bus #${index + 1}</div>
                                <div class="street-name">On: ${bus.streetName}</div>
                            </div>
                        </div>
                        <div class="progress-bar-container">
                            <div class="progress-bar" style="width: ${progress}%;"></div>
                        </div>
                        <button class="track-button" data-netid="${bus.netId}" data-routename="${routeName}">Track</button>
                    `;
                    routeElement.appendChild(busEntry);
                });
            } else {
                routeElement.innerHTML += `<div class="bus-entry"><div class="location-details"><div class="street-name">No active buses on this route.</div></div></div>`;
            }
            routesContainer.appendChild(routeElement);
        }
    }

    function updateNextBusDisplay(bus) {
        nextBusContainer.innerHTML = ''; // Clear previous
        if (!bus) return;
        
        const etaText = bus.eta ? bus.eta : '--';
        const nextBusCard = document.createElement('div');
        nextBusCard.className = 'next-bus-card';
        nextBusCard.innerHTML = `
            <img src="https://img.icons8.com/ios-filled/50/38bdf8/bus.png" alt="bus-icon" class="bus-icon">
            <div class="info">
                <div class="title">Next Arrival</div>
                <div class="route-name">${bus.routeName}</div>
            </div>
            <div class="eta">
                <div class="time">${etaText}</div>
                <div class="label">MIN</div>
            </div>
        `;
        nextBusContainer.appendChild(nextBusCard);
    }

    // --- Event Handlers for Buttons ---
    closeButton.addEventListener('click', () => {
        fetch(`https://AIBus/close`, { method: 'POST' });
    });

    routesContainer.addEventListener('click', (e) => {
        if (e.target.classList.contains('track-button')) {
            const netId = e.target.dataset.netid;
            const routeName = e.target.dataset.routename;
            fetch(`https://AIBus/trackBus`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ netId: netId, routeName: routeName })
            });
            // Close the UI after clicking track
            fetch(`https://AIBus/close`, { method: 'POST' });
        }
    });
});